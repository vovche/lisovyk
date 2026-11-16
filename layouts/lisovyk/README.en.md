# Why Lisovyk is laid out this way

[Українською](README.md) | English

This explains the decisions behind the layout. Installation is covered in the
[main README](../../README.en.md); the exact key list is in [keys.xkb](keys.xkb).

- [Apostrophe on the first level](#apostrophe-on-the-first-level)
- [The stress mark](#the-stress-mark)
- [Search in specific programs](#search-in-specific-programs)
- [Russian letters on their Ukrainian phonetic counterparts](#russian-letters-on-their-ukrainian-phonetic-counterparts)
- [Special characters without switching layouts](#special-characters-without-switching-layouts)
- [What it costs](#what-it-costs)

## Apostrophe on the first level

Unicode has three similar-looking characters that people use for the Ukrainian apostrophe:

| Character | Code | What it is in Unicode | Where in Lisovyk |
| --- | --- | --- | --- |
| `ʼ` | U+02BC | modifier letter (category Lm) | key left of `1`, no modifiers |
| `'` | U+0027 | punctuation, the straight ASCII apostrophe | AltGr + `є` |
| `’` | U+2019 | punctuation, right single quotation mark | AltGr + Shift + `2` |

In the base Ukrainian layout the first level of that key gives `'` (U+0027) and `ʼ` is on the second
(with Shift). Lisovyk swaps their priority: the character needed most often should be the easiest to
reach.

The Ukrainian apostrophe is part of the word, not punctuation: «пʼять», «обʼєкт», «Марʼяна». U+02BC
is the only one of the three that Unicode classifies as a letter, and every advantage follows from
that.

Advantages:

- **The word stays whole.** Programs that split text into words by character class do not break the
  word at the apostrophe: a double click selects «пʼять» entirely, "next word" does not stop in the
  middle, `\w` in regular expressions covers the whole word, a hashtag or username is not cut short.
- **No clash with quotes.** `'` opens a string in most programming languages, in SQL, the shell and
  CSV. The name «Мар'яна» has to be escaped there; «Марʼяна» does not.
- **Autocorrect leaves it alone.** Editors with "smart quotes" turn `'` into `’`, and sometimes into
  an opening `‘`. They do not touch the letter `ʼ`.
- **Usable in domain names.** U+0027 is forbidden in domains, which is why U+02BC was chosen for
  Ukrainian names with an apostrophe in the .укр zone
  ([the registrar's explanation](https://habr.com/ru/companies/ukrnames/articles/124134)). The rules
  have changed over time, so check the current ones before registering.
- **Unambiguous.** The character only ever means an apostrophe inside a word, which makes text easier
  to process: no guessing whether it is an apostrophe or a quote.

Disadvantages:

- **Most existing text is typed differently.** The web mostly has `'` or `’`. An exact search (Ctrl+F
  in a document, `grep`, a database lookup without normalisation) will not find «п'ять» for the query
  «пʼять», or the other way round. Large search engines mostly smooth this over; local search
  depends on the program: see [the table below](#search-in-specific-programs).
- **It is not accepted everywhere.** Bank and government forms, older systems and "letters and
  apostrophe only" validators may reject `ʼ` in a name or address. Use `'` (AltGr + `є`) there.
- **Spell checking.** Not every dictionary knows words spelled with U+02BC; such words may be
  underlined as errors.
- **Sorting and comparison.** «Марʼяна» and «Мар'яна» are different strings to a computer. In shared
  spreadsheets and databases this produces duplicates when people type it differently.
- **Old fonts.** A font without a U+02BC glyph falls back to another font and the character can look
  out of place. Current system fonts have it.

So both other characters stay within reach, and the default is the one that is right for ordinary
Ukrainian text.

## The stress mark

The same key left of `1`, with AltGr + Shift, gives the stress mark — U+0301, the "combining acute
accent". It is not a letter of its own but a stroke that sits above the preceding letter. Type it
right after the stressed vowel: `а`, then AltGr + Shift + the key left of `1`, gives `а́`.

What it is for:

- **Telling apart words that are spelled the same:** «за́мок» (castle) and «замо́к» (lock), «до́рога»
  (dear) and «доро́га» (road), «а́тлас» (atlas) and «атла́с» (satin).
- **Showing the correct pronunciation:** surnames, place names, rare words, terms — «Вінниче́нко»,
  «Богда́н Сту́пка», «фарту́х».
- **Teaching and reference texts:** dictionaries, textbooks, material for learners of Ukrainian.

What to expect:

- **It is a separate character.** `а́` is two characters, not one. Length counters count it
  separately, and Backspace removes only the mark in some programs and the letter with it in others.
- **Search ignores it only in some programs.** Browsers find «за́мок» for the query «замок»; code
  editors and Writer do not: see [the table below](#search-in-specific-programs). In text that has to
  be searched or processed, add stress marks only where they are really needed.
- **Appearance depends on the font.** Most current fonts place the stroke right above the letter;
  some shift it sideways.

The base layout has the stress mark on AltGr of this key. Lisovyk gives AltGr to the backtick
`` ` ``, as in the English layout, so the stress mark moved to AltGr + Shift.

## Search in specific programs

Whether search finds a word typed with a different apostrophe variant or with a stress mark. "Yes"
means it matches both ways: a query with one character finds text with the other, and vice versa.

| Program | `ʼ` ↔ `'` | `'` ↔ `’` | `ʼ` ↔ `’` | «замок» ↔ «за́мок» |
| --- | --- | --- | --- | --- |
| Firefox 160 | yes | yes | yes | yes |
| Chrome 157 | no | yes | no | yes |
| LibreOffice Writer 26.2 | no | only the query `'` finds `’` | no | no |
| VS Code 1.136, search across files | no | no | no | no |
| Vim 9.1 | no | no | no | no (yes with `\Z` in the pattern) |

How this was checked (November 2026, Ubuntu 26.04):

- **Firefox and Chrome** — a page with the test words and a `window.find()` call in headless mode.
  That is the same search engine as Ctrl+F, but the find bar itself was not tested.
- **LibreOffice Writer** — document search through the programming interface (UNO) with default
  parameters. The Find & Replace dialog has its own switches that may change the result.
- **VS Code** — the `ripgrep` bundled with VS Code, which it uses to search across files, was run
  directly. Search within an open file is built on JavaScript regular expressions; the same logic
  reproduced separately gives the same result, but the editor itself was not run for this.
- **Vim** — the `/` search in `vi` with no configuration.
- **Zed** was not tested.

Conclusion: only Firefox reliably finds a word with `ʼ` for a query with `'` or `’`. If other people
will search the text in other programs, this is a real drawback of U+02BC — and the only one that
habit cannot work around.

The advantage showed up in practice too: in Vim the `dw` ("delete word") command on «пʼять» deletes
the whole word, while on «п'ять» and «п’ять» it deletes only the first letter, up to the apostrophe.

## Russian letters on their Ukrainian phonetic counterparts

The layout is Ukrainian, but `э`, `ъ`, `ы` are occasionally needed: a quotation, a surname, a title.
The base layout puts them on the third level where they sit in the Russian layout: `ы` on the `і`
key, `э` on `є`, `ъ` on `ї`. Lisovyk puts them on the keys of letters that sound the same or play the
same role:

| Russian letter | Key in Lisovyk (with AltGr) | Why |
| --- | --- | --- |
| `э` | `е` | Ukrainian `е` sounds like Russian `э` |
| `ы` | `и` | Ukrainian `и` is the closest in sound to Russian `ы` |
| `ъ` | `ь` | the hard sign next to the soft sign: same role, opposite meaning |

Reasons:

- **No need to know the Russian layout.** "Same place as in Russian" only helps people who once
  touch-typed Russian. For everyone else it is three arbitrary positions to hunt for each time. A
  mapping by sound can be derived from the Ukrainian alphabet: to type «ы», recall that it sounds
  like «и».
- **It frees keys for special characters.** `є` and `ї` are `'` and `]` on the English layout. That
  is where Lisovyk puts those characters (see the next section), so the Russian letters cannot stay.
- **One rule for all three.** One explanation instead of three separate positions.

`ы` also stays on the `і` key, where the base layout has it: `і` got no new third-level symbols, so
there was no need to remove it.

## Special characters without switching layouts

The standard Ukrainian layout has no convenient `[ ] { } < > ; ' @ # ^ & | \ ~` or `` ` ``. Typing any
of them means switching to English, typing one character and switching back. Lisovyk puts them on
AltGr on the same physical keys they occupy in the English layout:

| Keys | With AltGr | With AltGr + Shift | In the English layout |
| --- | --- | --- | --- |
| `х` `ї` | `[` `]` | `{` `}` | `[` `]` and `{` `}` |
| `ж` `є` | `;` `'` | `:` `"` | `;` `'` and `:` `"` |
| `б` `ю` | `,` `.` | `<` `>` | `,` `.` and `<` `>` |
| `2` `3` `6` `7` `8` | `@` `#` `^` `&` `*` | | Shift + digit |
| left of `1` | `` ` `` | | `` ` `` (and `~` with Shift, as in English) |
| `\` | `\` and `|` without AltGr | | `\` and `|` |

The positions match English, so muscle memory carries over: the same movement, plus AltGr.

Who needs this:

- **Programmers and anyone working in a terminal.** Comments, commit messages and documentation are
  written in Ukrainian mixed with `` `code` ``, paths, `[links](...)`, and commands with `|`, `&`, `;`,
  `~`.
- **Anyone writing in chats.** Modern messengers and work chats understand markup: `` `code` `` and
  code blocks in triple backticks, `*bold*`, `_italic_`, `~strikethrough~`, `>` for a quote, `#` for
  headings and channels, `@` for mentions, `:` for emoji, `[text](link)`.
- **Anyone working with AI chat interfaces.** Prompts to assistants routinely contain code blocks,
  JSON fragments in `{ }`, tags in `< >`, Markdown lists and headings — in the middle of Ukrainian
  text.

In all these cases the special character sits inside a Ukrainian sentence. Switching layouts for a
single character costs time and, more importantly, causes mistakes: you forget to switch back and
type half a sentence in the wrong layout. With AltGr the layout never changes.

`\` and `|` are on the first and second levels of their key and `ґ` moves to the third and fourth:
`ґ` is one of the rarest Ukrainian letters, and the base layout already has it on AltGr + `г`, where
it stays in Lisovyk too.

## What it costs

The new characters took positions that held other ones in the base layout. Lisovyk no longer has:

- **`«` `»` `„` `“`** — they were on AltGr and AltGr + Shift of the `б` and `ю` keys. This is the most
  noticeable loss: Ukrainian typographic quotes now have to be typed another way (Compose, editor
  autocorrect).
- **`ё` `Ё`** — they were on AltGr of the `е` key, which now gives `э`.
- **`²` `§`** — they were on AltGr of the `2` and `3` keys.

Moved:

- **`<` `>`** on the `6` and `7` keys moved from AltGr to AltGr + Shift (and also appeared on `б`,
  `ю`).
- **`•`** on the `8` key moved from AltGr to AltGr + Shift.
- **`ґ` `Ґ`** on their own key moved to AltGr; AltGr + `г` works as before.
- **`'` (U+0027)** moved from the first level of the key left of `1` to AltGr + `є`.
- **`~`** on the key left of `1` moved from AltGr + Shift to Shift, and the stress mark from AltGr to
  AltGr + Shift.
