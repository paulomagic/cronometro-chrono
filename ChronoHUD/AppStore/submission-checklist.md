# App Store submission checklist

## Project and build

- [x] Bundle ID set to `com.pauloricardo.chronohud`.
- [x] Version set to `1.0.0` and build to `1`.
- [x] App Sandbox enabled.
- [x] Hardened Runtime enabled.
- [x] `PrivacyInfo.xcprivacy` declares no tracking, no collected data, and UserDefaults reason `CA92.1`.
- [x] `ITSAppUsesNonExemptEncryption` set to `false`.
- [ ] Confirm the Bundle ID exists in the Apple Developer account.
- [ ] Select the correct Team and Mac Distribution signing identity.
- [ ] Archive with the Release configuration on a clean build directory.
- [ ] Validate the archive in Organizer before upload.
- [ ] Run a final installation/launch test from the archived build.

## App Store Connect

- [ ] Create the macOS app record with name `CHRONO HUD`, primary language, Bundle ID, and SKU.
- [ ] Add pt-BR and en-US metadata from this folder.
- [ ] Confirm all metadata limits after pasting into App Store Connect.
- [ ] Choose Productivity as the primary category and review Utilities as the secondary category.
- [ ] Complete the current age-rating questionnaire accurately.
- [ ] Select “No, we do not collect data” in App Privacy.
- [ ] Confirm tracking is declared as not used.
- [ ] Publish the privacy policy on a public HTTPS page and replace both placeholder URLs.
- [ ] Publish a support page with real contact information and replace both placeholder URLs.
- [ ] Add App Review contact name, email, and phone.
- [ ] Paste the review notes and attach the uploaded build.
- [ ] Complete pricing, availability, content rights, and release settings.

## Screenshots

- [ ] Capture at least one and up to ten macOS screenshots per localization.
- [ ] Use an accepted 16:10 Mac size such as 1280×800 pixels.
- [ ] Export as PNG or JPEG without alpha.
- [ ] Show the normal HUD, compact mode, event log, settings, and history where useful.
- [ ] Verify screenshots contain no private data, debug UI, cursor artifacts, or misleading content.

## Final review

- [ ] Confirm the app name and subtitle are each at most 30 characters.
- [ ] Confirm promotional text is at most 170 characters.
- [ ] Confirm description is at most 4,000 characters.
- [ ] Confirm keywords are at most 100 UTF-8 bytes and contain no competitor/trademark terms.
- [ ] Proofread both localizations on the product-page preview.
- [ ] Submit only after App Store Connect reports no missing required fields.
