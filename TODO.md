# Future improvements

## Viewport-aware syntax highlighting

The current preview keeps syntax highlighting within a fixed token budget. If
an unusually token-dense file exhausts that budget, the rest of the text stays
readable but is not highlighted, even after the user scrolls to it.

A future version should highlight the visible viewport and a bounded region
around it on demand. Token ranges far outside that region should be evicted so
memory use remains bounded. The implementation must preserve lexer state at
chunk boundaries, avoid rescanning the entire file on every scroll, cancel
obsolete work during rapid scrolling, and keep the initial viewport responsive.
