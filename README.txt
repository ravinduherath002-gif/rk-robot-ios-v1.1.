RK ROBOT DOUBLE SIGNAL UPDATE

PHONE APP V9.2.6
- Added DOUBLE SIGNAL button.
- Tap ON  -> sends Y
- Tap OFF -> sends y
- Button highlights while active.
- Disconnect sends y automatically.

UNO V9.1.9
- A2 = LEFT signal
- A3 = RIGHT signal
- L turn = left LED blinks
- R turn = right LED blinks
- Y = both signal LEDs blink together
- y = double signal OFF
- Double signal overrides auto left/right blinking while enabled.

ESP32-CAM V6.5
- Y/y added to allowed commands.
- Controller loss also sends y so the double signal turns off safely.

IMPORTANT:
Upload/update all 3 because Y/y is a new command:
1. ESP32-CAM V6.5
2. UNO V9.1.9
3. Phone app V9.2.6

Flutter:
flutter clean
flutter pub get
flutter run

iOS READY PACKAGE
-----------------
This package keeps the uploaded V9.2.6 Flutter interface and Wi-Fi command logic.

- App name: RK ROBOT
- Landscape only
- Local Network permission included
- GitHub Actions workflow included for Windows -> unsigned IPA

Robot network in the uploaded source:
- IP: 192.168.4.1
- TCP port: 8080
