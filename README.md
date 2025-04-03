# ![DPSMeterIcon](https://github.com/AndyWilliams682/dps_meter/blob/main/assets/icon/icon.png) POE2 DPS Meter

[![](https://user-images.githubusercontent.com/4292308/153364874-dde23599-278c-4350-8d86-dadbc4b978b3.svg)](https://somsubhra.github.io/github-release-stats/?username=AndyWilliams682&repository=dps_meter)

[Latest Release](https://github.com/AndyWilliams682/dps_meter/releases/latest)

A tool that can calculate your DPS when fighting bosses in Path of Exile 2.

## Showcase

By default, the app will be collapsed. You can press the play button to start recording damage. Note this will only register damage against a single boss (as it is reading the accumulated damage number above their life bar). It also only tracks damage dealt to life.

IMAGE HERE OF COLLAPSED VERSION

Overall DPS considers the entire duration of the recording.
Recent DPS refers to the past 4 seconds.

IMAGE OF EXPANDED VERSION

Clicking the hamburger menu reveals the History tab, where all previous recordings from the current session are stored. You can click a radio button next to a measurement to set it as the baseline, and all other measurements will display a % More/Less DPS value. This is useful for comparing between two different options (such as swapping equipped items or deciding what support gems to use).

(The debug tab is just the logs. It can typically be ignored).

## How it works

It takes a screenshot of the Path of Exile 2 window once per second. That screenshot is processed by OpenCV and passed to Tesseract OCR for character recognition. I cannot guarantee 100% accuracy but in my testing it seems to read the numbers with minimal issue.

## Acknowledgements

This application is not affiliated with GGG in any way, and they do not officially approve any community-made tools. This application does not interact with the game in any way, it's just aggregating some information already provided to the player.

A big thank you to the plethora of packages used for Flutter/Dart, Rust, and the bridge between the two.
