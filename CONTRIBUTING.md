# Contributing

Thanks for helping. eazyConverter is built for screen reader and keyboard users first, so every change has to keep it that way.

## Before you open a pull request

1. Build for both "My Mac" and an iPhone simulator in Xcode 16 or later.
2. Test with VoiceOver on, on Mac and on iPhone:
   - Every control has a clear spoken name.
   - Everything can be reached with Tab and Shift-Tab and used with Space or Return.
   - The document can still be read with the arrow keys in Text view.
   - Headings, Tables and Pages rotors still work.
   - Status messages, such as "Saved", are announced without moving focus.
3. Don't add keyboard shortcuts that are a single letter, number or symbol. Every shortcut must include Command.
4. Don't add networking, analytics, third-party code, or anything that saves user content. See PRIVACY.md.

## Reporting a bug

Open an issue with:

- your device and operating system version
- the assistive technology you use and its version
- the file type you opened
- what you expected and what happened
