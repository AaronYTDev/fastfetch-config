# Changelog

Not the world's most organized changelog, but here's roughly what changed.

## V1.7.0

The testing build got promoted to stable, so all of that is now the normal build. The big stuff:

- Image logos. chafa, or the native Kitty graphics protocol if you're in Kitty. Auto mode picks whichever one fits your terminal.
- Sizing controls: `ff logo size 40x16` for an exact box, `ff logo width/height` to set one side and keep the aspect ratio.
- Logos re-fit to the terminal on every run, so wide ones stop wrapping.
- Experimental macOS support, with Homebrew or MacPorts.
- Backups, `diff`, and `clean` got portability fixes so they don't rely on GNU-only `stat` and `wc -L`.
- Fixed `ff diag` bailing out when jq was missing, `ff reset all` only handling one module, and picking a logo that already lives in your logos folder erroring on itself.

## V1.6.8 and before

Stuff happened. The git log has the details.
