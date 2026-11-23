# Cars

An iPhone widget (and a small app behind it) that shows both cars' batteries
at a glance:

- **ID.4**: battery, range and charging, read from
  [A Better Routeplanner](https://abetterrouteplanner.com)'s Telemetry API,
  which gets live data from the car through ABRP's Enode connection
  (VW doesn't let third-party apps in directly in the US).
- **EV3**: battery, range, charging/plugged in, time to full, locks and
  climate, read from the same server the Kia Access app uses.

Widgets: small and medium home-screen widgets, plus Lock Screen
rectangular and inline. iOS refreshes them on its own schedule (roughly every
15–60 minutes); opening the app refreshes right away.

Sign-ins and keys are typed into the app's Settings and kept in the phone's
keychain (shared between the app and the widget). Nothing secret is in this
repository.

## Setup

Uses the same signing secrets as the other apps, set on the
`mikemadden-looping` organization: `TEAMID`, `GH_PAT`, `FASTLANE_KEY_ID`,
`FASTLANE_ISSUER_ID`, `FASTLANE_KEY`, `MATCH_PASSWORD`, plus the existing
`Match-Secrets` repository. The repo needs to be public for the organization
secrets to apply.

1. **Actions → 1. Add identifier → Run workflow.** Registers
   `com.TEAMID.carstatus` and `com.TEAMID.carstatus.widget` and makes their
   profiles. No capabilities to turn on.
2. **App Store Connect → Apps → + → New App.** Platform iOS, name e.g.
   "Cars" (App Store Connect needs a name nobody else has, so something like
   "Madden Cars" if "Cars" is taken), bundle ID `com.TEAMID.carstatus`, any SKU.
3. **Actions → 2. Build to TestFlight → Run workflow.** About 10 minutes,
   then a few more for Apple to process. It rebuilds every Sunday so the
   TestFlight build doesn't expire.

**0. Check build** compiles on every push without signing.

## In the app

Settings (gear, top right):

- **Kia**: your Kia Access email and password → **Sign in**. The first time,
  Kia asks for a one-time code by email or text; enter it and the phone is
  remembered, so the widget can renew its own session after that. If Kia
  ever forgets the phone, the widget shows a warning and you sign in again
  here.
- **ABRP**: the Telemetry API key from Iternio, plus your ABRP user token for
  the ID.4 from ABRP's Live Data setup.
- **Diagnostics**: the last raw reply from each service, with a share button,
  for fixing things if a number looks wrong.

Your wife can install the same TestFlight build and sign in on her phone.

## Notes

- The Kia side follows the open-source
  [hyundai_kia_connect_api](https://github.com/Hyundai-Kia-Connect/hyundai_kia_connect_api)
  project (`KiaUvoApiUSA`). It's unofficial, so Kia can change it; if the EV3
  stops updating, check that project for fixes.
- The widget only reads the status the car last reported. It doesn't wake the
  car, so it won't drain the 12-volt battery.
