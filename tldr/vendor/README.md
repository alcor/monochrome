# Vendored code

`Readability.js` and `Readability-readerable.js` are Mozilla's Readability (https://github.com/mozilla/readability), release 0.6.0, commit `04fd32f72b448c12b02ba6c40928b67e510bac49`, unmodified. Copyright (c) 2010 Arc90 Inc. Licensed under the Apache License, Version 2.0. `LICENSE` in this folder is the licence text, and each file keeps its header.

The reader runs Readability on a clone of the page to find the article's root and its metadata (`tldr/core/extract.js`). Its cleaned HTML is not used.

To update: replace both files with the ones from a newer tag, change the release and commit above, and run `npm test`.
