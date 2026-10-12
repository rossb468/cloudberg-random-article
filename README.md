# Random Admiral Cloudberg

An unofficial reader for [Admiral Cloudberg](https://admiralcloudberg.medium.com)'s aviation (and other) disaster deep-dives on Medium, as a native iOS app plus a small web page.

- **iOS app** ([`ios/`](ios)) — browse and read the whole archive: a random-article picker, a searchable list with engagement stats, offline downloads, a customizable reader, and links to each article's Reddit discussion.
- **Web app** ([`app/`](app)) — the original one-page random-article picker.

## iOS app

Open [`ios/CloudbergRandom.xcodeproj`](ios/CloudbergRandom.xcodeproj) in Xcode and run the `CloudbergRandom` scheme. There are no package dependencies. To run on a device, pick your team under the target's Signing & Capabilities.

From the command line:

```bash
xcodebuild test -project ios/CloudbergRandom.xcodeproj -scheme CloudbergRandom -destination 'platform=iOS Simulator,name=iPhone 17'
```

### Features

- **Random** — a random article card, as in the web app.
- **Articles** — every article, searchable by title and subtitle, sorted by date, title, length, or engagement (overall, claps, Reddit upvotes, or comments). Swipe to download; long-press for the Reddit discussion and engagement stats.
- **Downloads** — reached from the Articles toolbar: download every article (text, and optionally images — about 3 GB in total) for offline reading, with progress, retry, and storage used. Any article you open is saved for offline reading as well.
- **Reader** — articles are parsed out of Medium's pages and laid out natively:
  - Reading preferences: seven color themes (including custom colors), nine typefaces, text size, line and paragraph spacing, margins, line width, justification, hyphenation, first-line indents, and keep-screen-on.
  - Full-screen image viewer with swipe, pinch and double-tap zoom, and share / save to Photos / copy.
  - Saved reading position with an offer to resume, and a "Back to 42%" pill whenever the position jumps far away (a status-bar tap, a hard fling, or navigating somewhere).
  - Bookmarks, and up/down buttons that step between bookmarks and sections (Admiral Cloudberg marks sections with "◊◊◊"); a contents sheet with a position scrubber.
  - A media browser showing all of an article's images and captions, grouped by section.
- **Reddit** — each article links to where it was posted on r/CatastrophicFailure.
- **Engagement stats** — Medium claps and responses plus Reddit upvotes, upvote ratio and comments, with each article's rank in the archive.

### Where the data comes from

| Data | Source | Stored in the repo? |
| --- | --- | --- |
| Article list, claps, responses | Medium article pages ([`scripts/update-catalog.swift`](scripts/update-catalog.swift)) | Yes: metadata only, in `Resources/articles.json` |
| Article text and images | Medium, fetched by the app | **No**: downloaded on-device only |
| Reddit posts, scores, comment counts | [Arctic Shift](https://arctic-shift.photon-reddit.com) Reddit archive ([`scripts/update-reddit-index.py`](scripts/update-reddit-index.py)) | Yes, in `Resources/reddit.json` |

Medium's page data is read from the Apollo cache Medium embeds in each page (`window.__APOLLO_STATE__`). Medium blocks curl and Python's HTTP clients but accepts Apple's `URLSession`, which is why the catalog script is Swift.

Reddit's API rejects unauthenticated clients, so Reddit numbers come from the Arctic Shift archive, which records each post about a day and a half after it's made. They reflect a post's first couple of days, not live totals. Medium numbers in the bundled catalog are refreshed whenever the app fetches an article page, or for every article via *Update Medium Stats* in the Articles sort menu.

### Updating the bundled data

```bash
swift scripts/update-catalog.swift --cache-dir /tmp/medium-pages
```

```bash
python3 scripts/update-reddit-index.py
```

Run the catalog script first: the Reddit index is keyed by the article list. `--cache-dir` is optional and saves fetched pages so a re-run doesn't refetch them.

### Code layout

| Folder | Contents |
| --- | --- |
| `App/` | App entry point, tab bar, and the `openArticle` action screens use to open articles |
| `Catalog/` | `Article` and the bundled catalog |
| `Random/` | Random article card |
| `ArticleList/` | Article list, search and sorting |
| `Offline/` | Medium page fetching and parsing, offline library, image loading, Library tab |
| `Reader/` | Reader document model, typesetting, reader UI, settings, image viewer, position, bookmarks, media browser |
| `Reddit/` | Reddit discussion index and links |
| `Stats/` | Engagement stats, ranking, stats UI |

The project uses folder-synchronized groups, so new files in these folders are picked up without editing `project.pbxproj`.

Debug builds accept launch arguments for jumping straight to a screen, which is handy in the simulator: `-rootTab articles`, `-debugOpenArticle <postID>`, `-debugOpenImage N`, `-debugShowReaderSettings YES`, `-debugShowReaderPanel contents|media|stats`, and `-debugDownloadNewest N`.

## Web app

```bash
./run.sh
```

This serves `app/` locally and opens it in your default browser (Ctrl+C to stop). Or serve it yourself with `cd app && python3 -m http.server 8743`, or just open `app/index.html`. It reads the same catalog as the iOS app, from `app/data.js`.

## Git history

Each feature was built on its own branch and merged into `main` with a merge commit, so a feature's changes can be reviewed with `git log main^1..<merge>` or backed out with `git revert -m 1 <merge>`:

| Branch | Feature |
| --- | --- |
| `chore/project-setup` | Project restructure and test target |
| `feature/article-list` | Master list of all articles; catalog refresh script |
| `feature/offline-library` | Download all articles for offline reading |
| `feature/reader` | Native reader: preferences, image viewer, position, bookmarks, media browser |
| `feature/reddit-discussions` | Links to each article's r/CatastrophicFailure discussion |
| `fix/random-card-layout` | Keep the random card on narrow screens |
| `feature/engagement-stats` | Engagement stats and sorting |

Later features build on earlier ones (for example, stats sort the article list and read Reddit data), so reverting an early feature may require reverting the ones after it.

## Credit

All article content and images belong to Admiral Cloudberg (Kyra Dempsey). This project is an unofficial reader: the repository contains only article metadata, and article text and images are downloaded by the app onto your device from Medium.
