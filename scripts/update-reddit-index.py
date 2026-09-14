#!/usr/bin/env python3
"""Builds the article -> r/CatastrophicFailure discussion index.

    python3 scripts/update-reddit-index.py

Reads ios/CloudbergRandom/Resources/articles.json and writes
ios/CloudbergRandom/Resources/reddit.json, keyed by Medium post id.

Reddit's own API rejects unauthenticated clients, so post and comment history
comes from the Arctic Shift archive (https://arctic-shift.photon-reddit.com).

Matching, most reliable first:
  1. Admiral_Cloudberg's own comment on a post links the Medium article
     ("Read the full article here: ..."). When one post links several
     articles, the one published closest to the post wins.
  2. Otherwise, a post created within two days of publication that shares a
     distinctive word (a flight number, a place name) with the article title.
  3. Otherwise, the post created closest to publication, within six hours.
"""

import json
import re
import sys
import time
import urllib.parse
import urllib.error
import urllib.request
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ARTICLES = ROOT / "ios/CloudbergRandom/Resources/articles.json"
OUTPUT = ROOT / "ios/CloudbergRandom/Resources/reddit.json"
API = "https://arctic-shift.photon-reddit.com/api"
AUTHOR = "Admiral_Cloudberg"
SUBREDDIT = "CatastrophicFailure"
DAY = 86400

MEDIUM_ID = r"medium\.com/(?:p/|[^\s)\]>]*?-)([0-9a-f]{8,12})(?![0-9a-f])"
FULL_ARTICLE = re.compile(r"full article here:?\s*\S*?" + MEDIUM_ID, re.I)
ANY_ARTICLE = re.compile(MEDIUM_ID)
COMMON_WORDS = set(
    """about after air aircraft airline airlines airport airways again against along also
    analysis another because before between crash crashes collision could death deadly
    disaster during every fatal first flight flights from have into midair near never
    over plane story that their there these they this through tragedy under what when
    where which while with would""".split()
)


def fetch(kind):
    """Every item Arctic Shift has for the author in the subreddit, newest first."""
    items, before = [], None
    while True:
        query = {"author": AUTHOR, "subreddit": SUBREDDIT, "limit": 100, "sort": "desc"}
        if before:
            query["before"] = before
        url = f"{API}/{kind}/search?{urllib.parse.urlencode(query)}"
        page = get(url)
        items += page
        if len(page) < 100:
            return items
        oldest = int(min(item["created_utc"] for item in page))
        if oldest == before:
            return items
        before = oldest
        time.sleep(0.5)


def get(url, attempts=4):
    """Arctic Shift's JSON "data" list, retrying transient failures."""
    request = urllib.request.Request(url, headers={"User-Agent": "cloudberg-reddit-index/1.0"})
    for attempt in range(1, attempts + 1):
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                return json.load(response)["data"]
        except urllib.error.HTTPError as error:
            detail = error.read().decode(errors="replace")[:300]
            print(f"  HTTP {error.code} for {url}: {detail}", file=sys.stderr)
            if attempt == attempts:
                raise
            time.sleep(5 * attempt)


def post_id(url):
    match = re.search(r"-([0-9a-f]{8,12})$", url)
    return match.group(1) if match else None


def distinctive_words(text):
    words = re.findall(r"[a-z0-9]+", text.lower())
    return {w for w in words if (len(w) >= 5 or w.isdigit()) and w not in COMMON_WORDS}


def main():
    articles = {post_id(a["url"]): a for a in json.loads(ARTICLES.read_text())}
    posts = {p["id"]: p for p in fetch("posts")}
    comments = fetch("comments")
    print(f"{len(articles)} articles, {len(posts)} posts, {len(comments)} comments", file=sys.stderr)

    def published(article_id):
        return articles[article_id]["publishedAt"] / 1000

    matches = defaultdict(set)  # article id -> reddit post ids

    linked = defaultdict(set)  # reddit post id -> article ids linked in the author's comments
    for comment in comments:
        reddit_id = comment["link_id"].removeprefix("t3_")
        body = comment.get("body") or ""
        found = FULL_ARTICLE.findall(body) or ANY_ARTICLE.findall(body)[:1]
        linked[reddit_id].update(i for i in found if i in articles)
    for reddit_id, article_ids in linked.items():
        if reddit_id in posts and article_ids:
            created = posts[reddit_id]["created_utc"]
            best = min(article_ids, key=lambda i: abs(published(i) - created))
            # A link to an article from weeks earlier is a reference (or a
            # copy-paste slip), not this post's article.
            if abs(published(best) - created) <= 7 * DAY:
                matches[best].add(reddit_id)

    claimed = {r for ids in matches.values() for r in ids}
    for article_id, article in articles.items():
        if article_id in matches:
            continue
        title_words = distinctive_words(article["title"])
        for reddit_id, post in posts.items():
            if reddit_id in claimed or abs(post["created_utc"] - published(article_id)) > 2 * DAY:
                continue
            if title_words & distinctive_words(post["title"]):
                matches[article_id].add(reddit_id)
        if article_id not in matches:
            # Newer posts describe the accident rather than repeating the title,
            # but go up within minutes of the article.
            close = [
                (abs(post["created_utc"] - published(article_id)), reddit_id)
                for reddit_id, post in posts.items()
                if reddit_id not in claimed and abs(post["created_utc"] - published(article_id)) <= 6 * 3600
            ]
            if close:
                matches[article_id].add(min(close)[1])

    index = {}
    for article_id, reddit_ids in matches.items():
        # Highest-scoring post first: reposts and removed duplicates sink.
        entries = sorted((posts[r] for r in reddit_ids), key=lambda p: p.get("score") or 0, reverse=True)
        index[article_id] = [
            {
                "id": p["id"],
                "title": p["title"],
                "permalink": "https://www.reddit.com" + p["permalink"],
                "createdAt": int(p["created_utc"]),
            }
            for p in entries
        ]

    OUTPUT.write_text(json.dumps(dict(sorted(index.items())), indent=1, ensure_ascii=False) + "\n")
    print(f"matched {len(index)}/{len(articles)} articles", file=sys.stderr)
    for article_id, article in articles.items():
        if article_id not in index:
            print(f"  no discussion found: {article['title']}", file=sys.stderr)


if __name__ == "__main__":
    main()
