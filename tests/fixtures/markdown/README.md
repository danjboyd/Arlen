# Markdown fixtures

`gfm_spec_examples.json` holds the 672 examples from the GitHub Flavored
Markdown Spec 0.29-gfm (`test/spec.txt` in cmark-gfm `0.29.0.gfm.13`), which
`tests/unit/MarkdownTests.m` renders and compares. Each entry has the example
number, its section, its extension tag (`""`, `table`, `strikethrough`,
`autolink`, `tagfilter` or `disabled`), and the Markdown and expected HTML with
the spec's `→` written as a real tab.

The spec text is licensed under
[CC-BY-SA 4.0](http://creativecommons.org/licenses/by-sa/4.0/) by John MacFarlane
and GitHub. To regenerate, extract every
`` ```````````````````````````````` example `` block from a new `spec.txt`
the same way.
