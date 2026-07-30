# Markix

Markix is a keyboard-first bookmark manager built on its own bounded Zig TUI
framework. It also includes a companion RSS reader that saves articles directly
into the same bookmark library.

```sh
zig build run
zig build run-rss
```

Bookmarks are stored atomically at `~/.markix/bookmarks.bin`.

Set `MARKIX_THEME=terminal` to inherit the terminal's default foreground,
background, and ANSI palette in either app:

```sh
MARKIX_THEME=terminal zig build run
MARKIX_THEME=terminal zig build run-rss
```

## RSS reader

`markix-rss` imports the existing Newsboat subscriptions from the first path it
finds:

1. `~/Developer/ads-zaneyos/config/newsboat/urls`
2. `~/.newsboat/urls`
3. `~/.config/newsboat/urls`

Feeds refresh in the background. Read state is stored atomically at
`~/.markix/rss-state.bin`. Parsed articles are cached at
`~/.markix/rss-cache.bin`; a cache younger than 30 minutes opens immediately
without an automatic network refresh. Articles are ordered newest first.
Feed additions, removals, and confirmed pruning are written atomically to the
active Newsboat URL file.

The reader preserves bounded article markup and renders headings, paragraphs,
lists, quotes, code, links, and images with the active theme. The image widget
negotiates Kitty graphics and Sixel support with the active terminal. When no
renderer is advertised it reserves no image rows and shows the styled image
link instead; `i` opens the image in the system browser. For terminals or
multiplexers that support Sixel without advertising it, use
`MARKIX_IMAGE_PROTOCOL=sixel`. `none` and `kitty` are also valid overrides.
Viewed images use a bounded 64-slot cache at `~/.markix/rss-images`.

Focusing Reader or entering full-screen mode fetches the linked article page in
the background when the feed only supplied an excerpt. The bounded readable
article markup is then stored in the RSS cache for subsequent launches.

| Key | Action |
| --- | --- |
| `h`, `l`, `Tab` | Move between categories, feeds, articles, and reader |
| `j`, `k` | Move or scroll in the focused pane |
| `g`, `G`, `Ctrl-d`, `Ctrl-u` | Jump or page through the focused pane |
| `Enter`, `o` | Open the article and mark it read |
| `i` | Open the article image |
| `b` | Bookmark the article in Markix |
| `m` | Toggle read/unread |
| `c` | Collapse or expand the focused section |
| `/` | Search titles, URLs, feeds, and summaries |
| `a`, `u` | Show all or unread articles |
| `r`, `R` | Refresh the selected feed or every feed |
| `A` | Add a feed URL and category |
| `d`, `d` | Remove the focused feed |
| `P`, `P` | Prune feeds failed by the latest completed full refresh |
| `v` | Enter or leave the full-screen reader from any pane |
| `Enter` | Toggle full-screen while the Reader pane is focused |
| `Escape` | Leave the full-screen reader |
| `?` | Toggle the keyboard help screen |
| `q`, `Ctrl-c` | Quit |

## Keys

| Key | Action |
| --- | --- |
| `h`, `l`, `Tab` | Move focus between scopes, bookmarks, and preview |
| `j`, `k` | Move or scroll in the focused pane |
| `g`, `G` | Jump to first or last bookmark |
| `Ctrl-d`, `Ctrl-u` | Move by a page |
| `Enter`, `o` | Open the selected bookmark |
| `a` | Add a bookmark |
| `/` | Search all bookmark fields |
| `f` | Toggle favorite |
| `d`, `d` | Confirm and delete |
| `r` | Fetch the selected page title and readable content again |
| `1`, `2` | Show all bookmarks or favorites |
| `v` | Toggle list and preview on narrow terminals |
| `q`, `Ctrl-c` | Quit |

The add form uses `Tab` and `Shift-Tab` to move between fields. Pressing
`Enter` on Notes saves the bookmark. Title is optional: Markix fetches the
page title, description, and readable content when it saves. Select a tag in
the Browse pane to restrict the bookmark list to that exact tag.

## Structure

Backend-neutral layout, style, input state, and the bounded layout tree live in
`src/framework`. Terminal rendering and patch generation live in
`src/backend/terminal`. The bookmark product lives in `src/app`, with
`src/main.zig` selecting the terminal backend.

```sh
zig build check
zig build check -Doptimize=ReleaseSafe
```
