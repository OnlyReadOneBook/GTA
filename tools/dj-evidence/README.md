# DJ 실패 증거 보존

`watch.pyw`는 기존 수익 로그의 `[dj-result]`, `멈춤: DJ:`, `보류: dj`를 읽어 사건별 폴더에 증거를 보존한다. 키·마우스 입력, 창 활성화, 게임 메모리 접근, 매크로 상태 변경은 하지 않는다.

- 감지 전 120초부터 마지막 인접 실패 로그 뒤 35초까지의 Steam 영상 조각과 초기화 조각을 복사한다. 작성 중인 조각은 제외하고 완성 후 수집한다.
- 기존 실패 PNG, 로그 앞뒤, 거래 보류 상태, 전경 PID·커서, 디스크의 소스·설정 사본과 해시를 보존한다. 소스 사본이 실행 중인 AHK가 로드한 버전과 같다는 보장은 없다.
- 읽기 위치와 수집 중 사건을 저장해 재시작 후 이어간다. 최초 설치 때 과거 로그를 새 사건으로 처리하지 않는다.
- 사건 폴더는 자동 삭제하지 않는다. 여유 공간이 2 GiB 미만이면 기존 자료를 보존하고 새 영상 복사를 멈추며 `status.json`에 오류를 남긴다.

Steam 녹화가 실제로 켜져 있어야 영상이 남는다. `incident.json`의 `video_chunks`가 비면 영상 확보 성공이 아니다. 시간 범위는 파일 수정 시각 기준이며 게임 내 실제 입력 수신 시각이 아니다. 전경 기록은 관찰 시점이고 모든 키 입력을 기록하는 기능은 아니다. 영상·진단 로그를 대조해야 표시 갱신, 화면 인식, 포커스 문제를 구분할 수 있다.

```powershell
pythonw tools/dj-evidence/watch.pyw --root C:/local/dj-evidence --steam 'C:/Program Files (x86)/Steam/userdata/ACCOUNT/gamerecordings/video' --repo C:/local/GTA
python -m unittest discover -s tools/dj-evidence -p 'test_*.py' -v
./tools/dj-evidence/install.ps1 -Pythonw C:/Python312/pythonw.exe -SteamVideo 'C:/Program Files (x86)/Steam/userdata/ACCOUNT/gamerecordings/video'
```

운영 시 로그인 및 1분 반복 Windows 작업으로 실행하고 중복 실행은 무시한다. Python GUI 실행기(`pythonw.exe`)를 사용해 전경 창을 만들지 않는다. `status.json`의 시각·PID·오류와 실제 사건 폴더를 확인한다. 종료 뒤 재실행은 가능하지만 살아 있는 프로세스의 정체를 감지하는 장치는 아니다.

영상 재생 파일은 해당 세션의 `init-stream0.m4s`와 숫자 순서의 `chunk-stream0-N.m4s`를 바이너리로 연결한 뒤 FFmpeg로 `-c copy` 리먹스한다. 사건마다 영상 번호 누락과 재생 가능 여부를 별도로 확인한다. 수집 성공은 과거 원인 규명이나 매크로 복구 성공을 뜻하지 않는다.
