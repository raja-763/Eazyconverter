# eazyConverter

An accessible file converter and document reader for Mac, iPhone and iPad. It's built for VoiceOver and keyboard users first.

Open a PDF, Word document, web page, text, Markdown, RTF file or picture. Move through it by headings, tables and pages, hear it read aloud, and save it as Word, PDF, HTML, plain text, Markdown or a PNG picture.

## Build and run

You need Xcode 16 or later on macOS 14 or later.

1. Open `eazyConverter.xcodeproj` in Xcode.
2. Select the eazyConverter project in the navigator, then the eazyConverter target, then the "Signing & Capabilities" tab. Choose your team from the Team pop-up. A free personal Apple ID team works for running on your own devices.
3. If Xcode says the bundle identifier is taken, change `com.example.eazyConverter` to something of your own, such as `com.yourname.eazyConverter`.
4. Choose a run destination with Control-Shift-0: "My Mac", an iPhone simulator, or your connected iPhone.
5. Press Command-R to build and run.

If the project won't open in your Xcode version, do this instead:

1. In Xcode, choose File > New > Project, then Multiplatform > App. Name it eazyConverter.
2. Delete the generated `ContentView.swift` and `EazyConverterApp.swift`.
3. Drag the `eazyConverter` folder from this download into the project and choose "Create folders".
4. In Signing & Capabilities, keep App Sandbox on, set "User Selected File" to Read/Write, and leave both network options off.
5. Set the deployment targets to iOS 17 and macOS 14.

## Reading with the arrow keys

The document screen shows only the document, nothing else. It opens in **Text** view: the whole document in one read-only text area, with keyboard focus already in it. Move into it and read with the arrow keys, the way you would in TextEdit or Pages:

- Up and Down Arrow read by line
- Option-Left and Option-Right read by word
- Left and Right Arrow read by character
- Command-Up and Command-Down go to the start or end

On iPhone, swipe up or down with the rotor set to Lines, Words or Characters, or use a keyboard's arrow keys.

Commands live in the **Document** menu in the menu bar (VO-M, then move to Document) and in the "Read aloud and navigate" toolbar button.

The VoiceOver rotor has Headings and Tables entries in Text view too. On Mac press VO-U, and on iPhone turn the rotor. Tables read one row per line, with each value next to its column name.

To start reading aloud from where the cursor is, press Command-Shift-R.

## One item at a time

Choose "Switch between text and one item at a time" from the Document menu (Command-Shift-T). On Mac this is a plain column, not a table, so you read item by item with VO-Right Arrow and never have to interact with it. Every heading, paragraph, list item and table row is its own VoiceOver element.

Headings are real headings with levels 1 to 6. On iPhone, set the rotor to Headings and swipe up or down. On Mac, press VO-U and pick the Headings rotor, or choose "Go to heading" (Command-Shift-H).

There are also two custom rotors:

- Headings, with the level of each
- Tables, with row and column counts

Page numbers from PDFs are left out, because they're layout rather than content.

Tables aren't groups you have to interact with. Each row is announced with its column names, such as "Row 2 of 5. Name: Alice, Role: Editor".

Every item has two VoiceOver actions: "Read aloud from here" and "Copy text". On iPhone, swipe up or down to pick one. On Mac, press VO-Command-Space.

Status messages, such as "Document opened, 12 headings, 3,400 words" or "Saved", are announced without moving your focus.

## Keyboard shortcuts (Mac, and iPad with a keyboard)

All shortcuts include Command, so they never clash with typing or with VoiceOver keys.

| Action | Keys |
| --- | --- |
| Upload file to convert | Command-O |
| Back to upload screen (clears the document) | Command-Shift-U |
| Convert and save | Command-Shift-S |
| Read aloud, pause or resume | Command-Shift-R |
| Stop reading | Command-Period |
| Next heading (reading) | Command-Option-Right Arrow |
| Previous heading (reading) | Command-Option-Left Arrow |
| Go to heading list | Command-Shift-H |
| Switch between text and one item at a time | Command-Shift-T |
| Read from selected item (iPhone and iPad list) | Return |

Everything else is reachable with Tab and Shift-Tab when Full Keyboard Access or "Keyboard navigation" is on in System Settings > Keyboard.

## Image descriptions

There's one upload button for everything. Choose "Upload file to convert" (Command-O) and pick a photo or screenshot. You get:

- **Image description**: the picture's shape and size, what it likely shows (for example "sky, outdoor, building"), and how many people, faces, cats or dogs were found.
- **Text in the picture**: any text, with large lines treated as headings.

Both are made on your device by Apple's Vision framework. Vision gives labels rather than full sentences, so the description lists likely contents instead of writing a caption. You can convert the result to Word, PDF or any other format, like any document.

## Read aloud

Reading only starts when you ask for it. By default it uses the voice and speed you set for VoiceOver. Turn off "Use my VoiceOver voice and speed" to choose a speed. Reading moves one block at a time, and you can jump by heading.

## What converts to what

| From | Structure kept |
| --- | --- |
| Word (.docx) | Headings, numbered and bulleted lists, tables, document title |
| HTML | Headings, lists, tables, code, image alt text, page title |
| Markdown | Headings, lists, tables, code |
| PDF | Headings and lists are worked out from text size, weight and layout. Scanned pages are read on your device. |
| RTF | Headings worked out from text size and weight |
| Pictures (PNG, JPEG, HEIC, TIFF, screenshots) | A description of what the picture likely shows, plus its text, both made on your device |
| Plain text | Paragraphs |

| To | What you get |
| --- | --- |
| Word | Built-in Heading 1 to 6 styles, real lists, tables with a repeating header row, title and language set |
| PDF | Tagged with H1 to H6, P, L, LI, Lbl, LBody, Table, TR, TH and TD, plus language and title |
| HTML | A `lang` attribute, `<main>`, real headings and lists, tables with `<th scope="col">`, dark mode |
| Plain text | Top headings underlined, lists marked |
| Markdown | Headings, lists, tables, code |
| PNG picture | High-contrast text with the full text stored in the PNG's Description field |

## Privacy

eazyConverter is designed so there's no personal data to protect, because it never keeps or sends any.

- It has no internet access. On Mac the App Sandbox network options are off. There's no networking code, no analytics, no crash reporting and no third-party code at all.
- Files are read into memory only. The app never writes a copy, a cache, a thumbnail or a history. It only writes a file when you save one, to the place you choose.
- "Clear document", or quitting the app, erases the document from memory.
- Text recognition (Vision), speech (AVSpeechSynthesizer) and language detection (Natural Language) all run on the device.
- On iPhone and iPad, the document is hidden from the app switcher snapshot.
- Exports contain only the title and language as metadata, with no author name or device details.
- The clipboard is only written when you choose Copy, and never read.
- `PrivacyInfo.xcprivacy` declares no tracking, no collected data and no required-reason APIs. On the App Store privacy label, choose "Data Not Collected".

This design avoids collecting personal data in the first place, which is the simplest position under GDPR, UK GDPR, CCPA and similar laws. I'm not a lawyer, though. If you publish the app, have someone qualified review your privacy policy and store listing.

## Repository contents

| Path | What it is |
| --- | --- |
| `eazyConverter/` | All app source code (SwiftUI, shared by Mac, iPhone and iPad) |
| `eazyConverter/Import/` | Readers for PDF, Word, HTML, Markdown, text, RTF and pictures |
| `eazyConverter/Export/` | Writers for Word, PDF, HTML, text, Markdown and PNG |
| `eazyConverter/Views/` | Screens, including the arrow-key reading view |
| `eazyConverter/PrivacyInfo.xcprivacy` | Apple privacy manifest |
| `eazyConverter.xcodeproj` | Xcode project |
| `.github/workflows/build.yml` | Builds the Mac and iPhone simulator versions on every push |
| `PRIVACY.md` | Privacy policy, ready for the App Store listing |
| `CONTRIBUTING.md` | How to contribute and the accessibility checks every change needs |
| `LICENSE` | MIT License |

## Known limits

- The Mac app builds and runs. The iPhone and iPad build hasn't been tested on a device yet.
- PDF headings are a best guess, because most PDFs don't store structure reliably. Check them before you share an export.
- Exported PDFs use Apple's PDF tagging API. Check one with PAC 2024 or Acrobat's accessibility checker before you rely on it for PDF/UA conformance.
- Pictures inside Word and PDF files aren't carried over. Alt text from HTML images is kept as text.
- Text recognition can misread names and numbers, especially in low-quality photos.
