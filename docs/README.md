# Splay's site and manual

This folder is the source of Splay's website, served by GitHub Pages at
https://shawntz.github.io/splay/. Read the manual there. Its pages draw their
figures with Jekyll includes, which GitHub's file view shows as raw
`{% include %}` lines.

- [Home page](https://shawntz.github.io/splay/), from `index.html`
- [Get started](https://shawntz.github.io/splay/start/), from `start.md`
- [Concepts](https://shawntz.github.io/splay/concepts/), from `concepts.md`
- [Layouts](https://shawntz.github.io/splay/layouts/), from `layouts.md`
- [Configuration](https://shawntz.github.io/splay/configuration/), from `configuration.md`
- [Commands](https://shawntz.github.io/splay/commands/), from `commands.md`
- [Changelog](https://shawntz.github.io/splay/changelog/), from `changelog.md`

`.github/workflows/pages.yml` builds this folder with GitHub's Jekyll and
deploys it on every push to `main` that changes it. To preview it on this Mac,
install Jekyll (`gem install jekyll jekyll-relative-links`) and run
`just docs`, which serves it at http://127.0.0.1:4000/splay/.

The demo animations in `assets/demo/` are rendered from Splay's layout engine.
They are not screen recordings, and their window contents are placeholders.
`border-development.md` is a note for working on window borders, and is left
out of the site.
