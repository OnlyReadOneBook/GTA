"""Preserve DJ failure evidence from existing logs and Steam recordings; no game input."""
import argparse
import ctypes
import hashlib
import json
import os
from pathlib import Path
import shutil
import time


def write_json(path, value):
    temporary = path.with_suffix('.tmp')
    temporary.write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding='utf-8')
    temporary.replace(path)


def read_json(path, default):
    try:
        return json.loads(path.read_text(encoding='utf-8'))
    except FileNotFoundError:
        return default


def failure(line):
    return ('[dj-result]' in line or '멈춤: DJ:' in line or '보류: dj ' in line)


def tail(path, count=131072):
    with path.open('rb') as stream:
        stream.seek(max(0, path.stat().st_size - count))
        return stream.read()


def foreground():
    if os.name != 'nt':
        return {}
    user = ctypes.windll.user32
    user.GetForegroundWindow.restype = ctypes.c_void_p
    hwnd = user.GetForegroundWindow()
    pid = ctypes.c_ulong()
    user.GetWindowThreadProcessId(ctypes.c_void_p(hwnd), ctypes.byref(pid))
    point = (ctypes.c_long * 2)()
    user.GetCursorPos(ctypes.byref(point))
    return {'hwnd': hwnd, 'pid': pid.value, 'cursor': list(point)}


class Watch:
    def __init__(self, root, log, steam, repo, temp):
        self.root, self.log, self.steam = Path(root), Path(log), Path(steam)
        self.repo, self.temp = Path(repo), Path(temp)
        self.root.mkdir(parents=True, exist_ok=True)
        self.state_path = self.root / 'state.json'
        self.state = read_json(self.state_path, {})
        self.state.setdefault('events', [])
        self.status = {'pid': os.getpid(), 'errors': []}

    def error(self, message):
        self.status['errors'] = (self.status['errors'] + [str(message)])[-10:]

    def snapshot(self, directory, suffix):
        files = [self.log, self.temp / 'gta-earn-state.txt', self.temp / 'gta-afk.log',
                 self.temp / 'gta-macro.log', Path.home() / 'gta-kick' / 'observations.jsonl']
        for source in files:
            try:
                (directory / (source.name + '.' + suffix)).write_bytes(tail(source))
            except OSError as exc:
                self.error(f'{source}: {exc}')
        write_json(directory / ('foreground.' + suffix + '.json'), foreground())

    def begin(self, line, now):
        # Adjacent diagnostic and hold lines belong to the same failed transaction.
        if self.state['events'] and now - self.state['events'][-1]['at'] < 60:
            event = self.state['events'][-1]
            event['lines'].append(line)
            event['until'] = max(event['until'], now + 35)
            event['done'] = False
            return
        name = time.strftime('%Y%m%d-%H%M%S', time.localtime(now)) + '-' + hashlib.sha256(line.encode()).hexdigest()[:8]
        directory = self.root / name
        directory.mkdir(exist_ok=True)
        event = {'name': name, 'at': now, 'until': now + 35, 'lines': [line], 'done': False}
        self.state['events'].append(event)
        self.snapshot(directory, 'before')
        sources = directory / 'source'
        sources.mkdir(exist_ok=True)
        hashes = {}
        for relative in ['Main.ahk', 'Features/Earn/EarnTasks.ahk', 'Features/Earn/EarnCore.ahk',
                         'Features/Earn/Earner.ahk', 'Features/Earn/EarnScreen.ahk', 'Config.ini']:
            source = self.repo / relative
            try:
                data = source.read_bytes()
                (sources / relative.replace('/', '_')).write_bytes(data)
                hashes[relative] = hashlib.sha256(data).hexdigest()
            except OSError as exc:
                self.error(str(exc))
        write_json(directory / 'source-hashes.json', hashes)

    def collect(self, event, now):
        directory = self.root / event['name']
        for session in self.steam.glob('bg_3240220_*'):
            chunks = []
            for source in session.glob('chunk-stream0-*.m4s'):
                stat = source.stat()
                if event['at'] - 120 <= stat.st_mtime <= event['until'] and now - stat.st_mtime >= 2:
                    chunks.append(source)
            if not chunks:
                continue
            target = directory / session.name
            target.mkdir(exist_ok=True)
            for source in [session / 'init-stream0.m4s'] + chunks:
                destination = target / source.name
                if not destination.exists():
                    if shutil.disk_usage(self.root).free < 2 * 1024**3:
                        raise OSError('Less than 2 GiB free; existing evidence preserved, video copy paused')
                    staging = destination.with_suffix('.copying')
                    shutil.copy2(source, staging)
                    staging.replace(destination)
        for source in (self.temp / 'claude').glob('gta-earn-fail-*.png'):
            if event['at'] - 5 <= source.stat().st_mtime <= event['until']:
                shutil.copy2(source, directory / source.name)
        if now > event['until'] + 5:
            self.snapshot(directory, 'after')
            event['done'] = True
        retained = sorted(str(p.relative_to(directory)) for p in directory.glob('bg_*/chunk-stream0-*.m4s'))
        write_json(directory / 'incident.json', dict(event, video_chunks=retained,
                   errors=self.status['errors'], note='Observation time; source hashes do not prove loaded AHK version. Video uses file timestamps.'))

    def poll(self, now=None):
        now = time.time() if now is None else now
        try:
            stat = self.log.stat()
            identity = [stat.st_dev, stat.st_ino]
            if 'offset' not in self.state:
                # Installation never replays historic failures as new incidents.
                self.state.update(offset=stat.st_size, identity=identity)
            elif self.state.get('identity') != identity or stat.st_size < self.state['offset']:
                self.state.update(offset=0, identity=identity)
            with self.log.open('rb') as stream:
                stream.seek(self.state['offset'])
                data = stream.read(1024 * 1024)
            end = data.rfind(b'\n') + 1
            for raw in data[:end].splitlines():
                line = raw.decode('utf-8', errors='replace')
                if failure(line):
                    self.begin(line, now)
            self.state['offset'] += end
            self.status['log_ok'] = True
        except OSError as exc:
            self.status['log_ok'] = False
            self.error(str(exc))
        for event in self.state['events']:
            if not event['done']:
                try:
                    self.collect(event, now)
                except OSError as exc:
                    self.error(str(exc))
        # Incident folders remain intact; only finished cursor bookkeeping is bounded.
        self.state['events'] = [e for e in self.state['events'] if not e['done'] or now - e['until'] < 86400]
        write_json(self.state_path, self.state)
        self.status.update(at=now, foreground=foreground(), pending=sum(not e['done'] for e in self.state['events']))
        write_json(self.root / 'status.json', self.status)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--root', required=True)
    parser.add_argument('--steam', required=True)
    parser.add_argument('--repo', required=True)
    parser.add_argument('--log', default=str(Path(os.environ.get('TEMP', '.')) / 'gta-earn.log'))
    parser.add_argument('--once', action='store_true')
    args = parser.parse_args()
    handle = None
    if os.name == 'nt':
        kernel = ctypes.WinDLL('kernel32', use_last_error=True)
        kernel.CreateMutexW.restype = ctypes.c_void_p
        handle = kernel.CreateMutexW(None, False, 'Local\\GTADJEvidence-' + hashlib.sha256(str(Path(args.root).resolve()).casefold().encode()).hexdigest()[:16])
        if not handle:
            raise ctypes.WinError(ctypes.get_last_error())
        if ctypes.get_last_error() == 183:
            kernel.CloseHandle(ctypes.c_void_p(handle))
            return
    watch = Watch(args.root, args.log, args.steam, args.repo, Path(args.log).parent)
    try:
        while True:
            watch.poll()
            if args.once:
                break
            time.sleep(1)
    finally:
        if handle:
            kernel.CloseHandle(ctypes.c_void_p(handle))


if __name__ == '__main__':
    main()
