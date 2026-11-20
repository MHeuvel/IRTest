# UnityIRedux 1.0

An iOS app (SwiftUI, iOS 16 and later, English interface) that controls the **Gear4 UnityRemote**, a Bluetooth infrared blaster for iPhone (an MFi accessory, ExternalAccessory protocol `com.gear4.unityremote`). The original 32-bit app no longer runs; this app replaces it. The signal format and the commands come from analysing the original app (version 1.7.1) and from measurements on a real unit.

Supported unit types: Axum II, Gondar I and Gondar II. The app was developed and tested on a **Gondar II** only (firmware 0.25.0, hardware 1.3.2); the other two follow the same tables from the original app but are untested.

## Quick start
1. Install the IPA (see "Building"). Open the app. If no unit is connected a banner shows "No UnityRemote found. Connect the UnityRemote in iOS Settings > Bluetooth, or tap Connect."
2. **Connect the unit in iOS Settings > Bluetooth.** The app sees it at once and opens its connection by itself (it also checks when the app comes to the foreground and every 2 seconds). A unit is connected to one phone or iPad at a time and reconnects by itself to the one it was used with last: if it does not show up, turn Bluetooth off on the other device. The Connect button in the banner opens the iOS picker for a new unit (it lists units in pairing mode that are not connected to another device); if nothing is connected afterwards a message says so.
3. Tap the device name at the top to choose a device; the gear opens the device list (add a device with type, brand and code, edit, delete) and Settings. Press Power, VOL, CH ...

## Devices
- A device has a **type** (39 types: TV, receiver, DVD, satellite, ...), a **brand** and an infrared **code** from the original database (arrow keys or a list to choose the code; try codes until one works). The type decides the pages and the base type that goes into the command.
- **Learned remote**: a device without a code; only keys you learn or import (Custom page). It can get standard pages (see "Flipper").
- In the device list: swipe for **Edit** and **Delete**. Tap the code bar to choose another code for the device; that screen only lists the codes.
- Settings (gear): Devices, Settings (chip, connection, backup, log, About).

## The pages
Swipe left and right, or tap the page bar. A page without any visible button leaves the bar (Custom stays).
- **Power row** (top, all pages): Power, On and Off.
- **Remote page**: channel and volume capsules (VOL + and -, CH + and - or Tune on audio) around the arrow pad (arrows and OK), the color keys (TV and disc, Red, Green, Yellow, Blue) and below them the **buttons block**: eight buttons, four per row. TV: Input, Menu, Guide, Info, Back, Exit, Mute, Last. Audio: Input, Source, Menu, Info, Mute, Exit, Back, Band. Disc: Menu, Title, Info, Eject, Back, Exit, Repeat, Random. On base type 11 Input is Home.
- **Numbers page**: 1 to 9, then bottom left Exit (TV) or Eject (disc player; empty on audio), 0 and Enter (+10 on a disc player).
- **Media page**: Reverse, Play, Fast forward, Pause, Stop, Record on a TV; with Previous, Next and Eject on audio and disc players.
- **Custom page**: your learned or imported keys as tiles (see "Learning").
- Press and hold **VOL and CH** (after 0.4 s) repeats the key until you let go (the unit repeats by itself; the app sends the stop, never sooner than 0.5 s after the start; a safety stop after 10 s).
- A button shows the **name its code gives the key** (see "Key names"). A key the unit has no code for says "Function not available".
- Keys are sent one at a time (the unit needs about half a second per command). Up to 5 taps are queued; a tap while the unit is busy waits.

## Edit device
Swipe a device > Edit.
- **Name**.
- **Power options**: switches for Power, Power On and Power Off (a hidden button leaves the Power row), and **Hold power** (- and + in steps of 250 ms, off up to 5 s): with a value the Power key is transmitted that long (command 03), for devices that only react when Power is held. Off sends it once.
- **Groups**: Volume, Channel (Tune), Arrow pad, Color keys: switch off a group and it leaves the remote page.
- **Number keys > Show page**: hides the Numbers page.
- **Buttons block**, **More buttons** (other keys the Gear4 knows, off by default, added to the block when on: Setup, Favorite, Wide, List, +100, PIP, HDMI and so on) and **Media page** keys: per key a switch, the name, a pencil and a signal icon.
  - The signal icon sends the key (Test); use it to find out what a key does for this device and switch off what does nothing.
  - The pencil gives the button **your own name** on this device ("Use name from code" removes it).
  - Notes under a key: "Code: <name>" (name from the code when you gave your own), "Standard name: <name>" (only when the renamed button has the same name as another button, for example two buttons called Back), "This code gives it no name" (usually does nothing), "Not available" (this chip has no key for it), "No signal assigned" (learned remote), "Flipper key: <name>".
- **Flipper keys**: how many standard buttons send an imported signal; touch and hold a key row to remove one, or remove all.
- **Back to standard buttons** restores all switches. For a learned remote: **Standard pages** (Custom only, TV, Audio, Disc player).
- Hidden or added buttons are stored per device and are part of the backup. Existing devices show everything until you change something.

## Key names
The unit has numbered keys and every code decides what a number means. On a Samsung TV code the keys that a standard remote calls Pause, Reverse, Fast forward and Record are HDMI 1 to 4. The app has the key names of the original database (2,476 codes, `Sources/KeyNames.txt`): text buttons show the name the code gives, icon buttons keep their icon when the name means the same (Play, Stop, ...) and otherwise show the name as text (in white). Chip key numbers: Gondar II uses its own numbering (profile 2), Axum II the app's slot numbers (profile 1); the Gondar I numbering (profile 0) is assumed.

## Learning and the Custom page
- Tap the radio-waves icon at the top (left of the gear) for **learn mode** on the Custom page: Add (+), tap a tile for Relearn, Rename or Delete, and Reorder. Outside learn mode a tile sends its signal.
- **Learning**: hold the original remote less than 1 cm from the unit's learn receiver (next to the flashing LED), tap Start learning, press one key once. The screen shows the raw data, a **Recording** line that says what the signal is (for example "Samsung32 · address 07 · command 07 · check OK") with warnings, a pattern check (the number of leading bytes to skip is guessed, default 2), Replay and Save. A recording that looks wrong can still be saved; test it with Replay first. Learning fails (status 08 after about 6 seconds) for remotes without infrared for that key (for example the LG Magic Remote pointer keys).
- **Enter raw data**: type or paste the hex of a signal (`00 00 LL ...`) instead of learning.
- Learned keys are not erased from the unit (the unit stores them at a fixed place; the app keeps the signal itself).

## Flipper-IRDB
- **Import**: Custom page > learn mode > "Import Flipper file". Choose "Search Flipper database" (built in, CC0) or a `.ir` file. You see per key whether it can be converted, a Test icon and a switch.
- **Built-in database** (`Sources/FlipperDB.txt`): 8,883 remotes, 169,015 keys with a protocol and 128,732 raw recordings already converted to the chip signal (at most 13 pulse pairs, 244 bytes; 138 recordings are too long and 164 have more than 13 pairs and are left out). Browse category > brand > model or search brand/model.
- **Protocols**: Samsung32, NEC, NECext, NEC42, NEC42ext, SIRC (12, 15, 20 bits, three frames), RC5, RC5X, RC6, Kaseikyo (Panasonic, Denon, JVC), RCA, Pioneer, and raw. NEC42, NEC42ext, RCA, Pioneer and Kaseikyo are built from the protocol descriptions and untested on the chip.
- **On the standard buttons**: with "Put matching keys on the standard buttons" on (default for devices with standard pages) a key whose name matches a button (Power, Vol_up, Ch_next, Menu, Mute, arrows, OK, 0 to 9, Play, Pause, Rewind, Exit, Back, Source, Info, Guide, colors, HDMI, Favorite, List, ...) replaces what that button sent. The first matching key wins; Enter becomes the channel Enter when there is also an OK. The other keys go to the Custom page. A button with an imported signal is sent once (press and hold only works for the unit's own keys); a hidden button the key lands on becomes visible.
- **Learned remote with standard pages**: choose Standard pages in Edit (or in the import screen); buttons without a signal say "No signal for this button".
- `tools/make_flipperdb.py <Flipper-IRDB checkout> Sources/FlipperDB.txt` rebuilds the database file. Many keys have no separate Power On and Power Off in Flipper files; switch those buttons off under Power options.

## Settings
- **UnityRemote unit > Chip**: Axum II, Gondar I or Gondar II (set per unit).
- **Connection**: the status of the connection (the app connects by itself; see Quick start).
- **Backup**: Save as file (JSON) and Restore from file (replaces everything after confirmation). Includes devices, learned keys, hidden and added buttons, own names, Flipper keys and Hold power.
- **Log**: the traffic with the unit (Copy, Clear); useful for problems. **About**.

## Signal format (for developers)
- Frame `AA 55 | LEN | CMD | payload | CHK`, LEN = bytes after LEN, CHK = NOT(XOR of all earlier bytes).
- Key: CMD 01, payload `chip(4) | 05 | 01 | V_hi V_lo | key | 80` with V = ((base type - 1) << 12) | code. Continuous: CMD 02 with last byte `00`; stop `AA 55 02 04 06`. Power with a duration: CMD 03 `ms_hi ms_lo | ... | 00`. Chip IDs: Axum II `55 49 42 31`, Gondar I and II `BC AC 0D 00`.
- Learning: `AA 55 0A 01 | chip(4) | 03 | 12 | 00 00 | CHK`. Replay: CMD 01, `chip(4) | L+4 | 10 | 00 00 90 | signal`.
- Signal = `00 00 LL` + body. Table form: `00 | carrier | pairs | (mark, space in 2 µs)×pairs | symbols | 4-bit symbols`; compact form (Samsung32): `00 | carrier | 80 | A2 | symbols (1 leader, 2 bit 1, 3 bit 0, 0 end)`. Carrier byte = round(8 MHz / frequency).

## Tested and not tested
Tested on a Gondar II with Samsung, LG and Philips TVs, a Denon receiver (briefly) and a Sony amplifier (partly): connecting, single keys, press and hold, Hold power, learning and replay, Flipper hex in both forms, import from a file and from the database, Flipper keys on the standard buttons, backup and restore, key names, own names, all Edit screens.
Not tested: Axum II and Gondar I, Sony (40 kHz) and RC5/RC6 (36 kHz) on all devices, NEC42, NEC42ext, Kaseikyo, RCA and Pioneer, most raw recordings on other brands, receiver, satellite, DVD and Blu-ray pages on real devices.

## Building (GitHub Actions)
1. Use a **private** repository: `Sources/CatalogData.swift` (codes) and `Sources/KeyNames.txt` (key names) come from the original app's database.
2. Upload `project.yml`, `README.md`, `tools/` and the `Sources` folder (including `FlipperDB.txt`, 16 MB).
3. Create `.github/workflows/build.yml` (Add file > Create new file) with the contents of the supplied file. The workflow uses XcodeGen on macos-latest and builds an unsigned IPA.
4. Actions > Build IPA > Run workflow. Download the IPA from Artifacts and install it (for example with Impactor).

## Project layout (`Sources`)
`UnityIReduxApp` (entry), `ContentView` (main screen, pages, sheets), `Pages` and `Components` (page layout, buttons, press and hold gesture), `KeyConfig` (groups, standard block, extra keys, hidden keys), `KeyNames` and `KeyNames.txt` (names per code), `DeviceEditView` (Edit device), `DevicesViews` (device list, code screen, Settings), `CustomViews` (Custom page, learn screen, reorder), `Models` (devices, store), `Catalog` and `CatalogData` (types, brands, codes), `Protocol` (packets, key tables per chip), `RemoteController` (Bluetooth session, queue, hold, learning, replay, log), `IRConvert` (chip signal encoder, protocols, Flipper parser, recording analysis), `FlipperImport`, `FlipperDatabase` and `FlipperDB.txt`, `FlipperMap` (names to standard buttons), `Backup`.
