# Random Admiral Cloudberg

An app (web + iOS) that serves up a random article from [Admiral Cloudberg](https://admiralcloudberg.medium.com)'s aviation (and other) disaster deep-dives on Medium. Tap the button, get a new random pick; tap "Read full article" to open it on Medium.

There are two versions of the app, sharing the same underlying article data: a static web app in [`app/`](app), and a native SwiftUI iOS app in [`ios/`](ios).

## How it works

- [`app/data.js`](app/data.js) is a pre-built, static list of every real article Admiral Cloudberg has published on Medium (title, subtitle, cover image, word count, reading time, publish date, and URL). It was generated once by paginating through Medium's internal profile API and filtering out short comment/reply posts that aren't real articles. [`ios/CloudbergRandom/Resources/articles.json`](ios/CloudbergRandom/Resources/articles.json) is the same data set, converted to plain JSON and bundled into the iOS app. Neither app makes any API calls at runtime.
- The web app ([`app/index.html`](app/index.html) + [`app/app.js`](app/app.js)) and the iOS app ([`ios/CloudbergRandom`](ios/CloudbergRandom)) both just pick a random entry from that list and render it, then swap in a new one on tap. No build step, no backend.
- "Read full article" opens the real article on Medium (in a new browser tab on web, in an in-app Safari view on iOS), since Medium doesn't allow its articles to be embedded elsewhere.

## Running the web app

**Easiest way:**

```bash
./run.sh
```

This starts a local web server for the `app/` folder and opens it in your default browser. Press `Ctrl+C` in the terminal to stop the server when you're done.

**Manually:**

```bash
cd app
python3 -m http.server 8743
```

then open `http://localhost:8743` in a browser. You can also just double-click `app/index.html` to open it directly, with no server at all.

## Running the iOS app

Open [`ios/CloudbergRandom.xcodeproj`](ios/CloudbergRandom.xcodeproj) in Xcode, pick an iPhone simulator (or a signed-in device), and hit Run. It's a plain SwiftUI app with no external dependencies or package requirements — no CocoaPods, no SPM packages, nothing to fetch before it'll build.

From the command line:

```bash
xcodebuild -project ios/CloudbergRandom.xcodeproj -scheme CloudbergRandom \
  -destination 'platform=iOS Simulator,name=iPhone 16' build
```

## Updating the article list

`app/data.js` (and its iOS counterpart, `ios/CloudbergRandom/Resources/articles.json`) are point-in-time snapshots, so they won't include articles published after they were generated. To refresh them, the article data needs to be re-pulled from Medium's profile stream API for the account and re-filtered for real articles (as opposed to short reply/comment posts), then saved back into `app/data.js` as `window.ARTICLES = [...]` and re-exported as JSON for the iOS app.

## Credit

All article content and images belong to Admiral Cloudberg (Kyra Dempsey). This project is just an unofficial random-article picker linking out to her work — it doesn't republish or host any article text.
