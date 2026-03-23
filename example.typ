// Simple numbering for non-book documents
#let equation-numbering = "(1)"
#let callout-numbering = "1"
#let subfloat-numbering(n-super, subfloat-idx) = {
  numbering("1a", n-super, subfloat-idx)
}

// Theorem configuration for theorion
// Simple numbering for non-book documents (no heading inheritance)
#let theorem-inherited-levels = 0

// Theorem numbering format (can be overridden by extensions for appendix support)
// This function returns the numbering pattern to use
#let theorem-numbering(loc) = "1.1"

// Default theorem render function
#let theorem-render(prefix: none, title: "", full-title: auto, body) = {
  if full-title != "" and full-title != auto and full-title != none {
    strong[#full-title.]
    h(0.5em)
  }
  body
}
// Some definitions presupposed by pandoc's typst output.
#let content-to-string(content) = {
  if content.has("text") {
    content.text
  } else if content.has("children") {
    content.children.map(content-to-string).join("")
  } else if content.has("body") {
    content-to-string(content.body)
  } else if content == [ ] {
    " "
  }
}

#let horizontalrule = line(start: (25%,0%), end: (75%,0%))

#let endnote(num, contents) = [
  #stack(dir: ltr, spacing: 3pt, super[#num], contents)
]

#show terms.item: it => block(breakable: false)[
  #text(weight: "bold")[#it.term]
  #block(inset: (left: 1.5em, top: -0.4em))[#it.description]
]

// Some quarto-specific definitions.

#show raw.where(block: true): set block(
    fill: luma(230),
    width: 100%,
    inset: 8pt,
    radius: 2pt
  )

#let block_with_new_content(old_block, new_content) = {
  let fields = old_block.fields()
  let _ = fields.remove("body")
  if fields.at("below", default: none) != none {
    // TODO: this is a hack because below is a "synthesized element"
    // according to the experts in the typst discord...
    fields.below = fields.below.abs
  }
  block.with(..fields)(new_content)
}

#let empty(v) = {
  if type(v) == str {
    // two dollar signs here because we're technically inside
    // a Pandoc template :grimace:
    v.matches(regex("^\\s*$")).at(0, default: none) != none
  } else if type(v) == content {
    if v.at("text", default: none) != none {
      return empty(v.text)
    }
    for child in v.at("children", default: ()) {
      if not empty(child) {
        return false
      }
    }
    return true
  }

}

// Subfloats
// This is a technique that we adapted from https://github.com/tingerrr/subpar/
#let quartosubfloatcounter = counter("quartosubfloatcounter")

#let quarto_super(
  kind: str,
  caption: none,
  label: none,
  supplement: str,
  position: none,
  subcapnumbering: "(a)",
  body,
) = {
  context {
    let figcounter = counter(figure.where(kind: kind))
    let n-super = figcounter.get().first() + 1
    set figure.caption(position: position)
    [#figure(
      kind: kind,
      supplement: supplement,
      caption: caption,
      {
        show figure.where(kind: kind): set figure(numbering: _ => {
          let subfloat-idx = quartosubfloatcounter.get().first() + 1
          subfloat-numbering(n-super, subfloat-idx)
        })
        show figure.where(kind: kind): set figure.caption(position: position)

        show figure: it => {
          let num = numbering(subcapnumbering, n-super, quartosubfloatcounter.get().first() + 1)
          show figure.caption: it => block({
            num.slice(2) // I don't understand why the numbering contains output that it really shouldn't, but this fixes it shrug?
            [ ]
            it.body
          })

          quartosubfloatcounter.step()
          it
          counter(figure.where(kind: it.kind)).update(n => n - 1)
        }

        quartosubfloatcounter.update(0)
        body
      }
    )#label]
  }
}

// callout rendering
// this is a figure show rule because callouts are crossreferenceable
#show figure: it => {
  if type(it.kind) != str {
    return it
  }
  let kind_match = it.kind.matches(regex("^quarto-callout-(.*)")).at(0, default: none)
  if kind_match == none {
    return it
  }
  let kind = kind_match.captures.at(0, default: "other")
  kind = upper(kind.first()) + kind.slice(1)
  // now we pull apart the callout and reassemble it with the crossref name and counter

  // when we cleanup pandoc's emitted code to avoid spaces this will have to change
  let old_callout = it.body.children.at(1).body.children.at(1)
  let old_title_block = old_callout.body.children.at(0)
  let children = old_title_block.body.body.children
  let old_title = if children.len() == 1 {
    children.at(0)  // no icon: title at index 0
  } else {
    children.at(1)  // with icon: title at index 1
  }

  // TODO use custom separator if available
  // Use the figure's counter display which handles chapter-based numbering
  // (when numbering is a function that includes the heading counter)
  let callout_num = it.counter.display(it.numbering)
  let new_title = if empty(old_title) {
    [#kind #callout_num]
  } else {
    [#kind #callout_num: #old_title]
  }

  let new_title_block = block_with_new_content(
    old_title_block,
    block_with_new_content(
      old_title_block.body,
      if children.len() == 1 {
        new_title  // no icon: just the title
      } else {
        children.at(0) + new_title  // with icon: preserve icon block + new title
      }))

  align(left, block_with_new_content(old_callout,
    block(below: 0pt, new_title_block) +
    old_callout.body.children.at(1)))
}

// 2023-10-09: #fa-icon("fa-info") is not working, so we'll eval "#fa-info()" instead
#let callout(body: [], title: "Callout", background_color: rgb("#dddddd"), icon: none, icon_color: black, body_background_color: white) = {
  block(
    breakable: false, 
    fill: background_color, 
    stroke: (paint: icon_color, thickness: 0.5pt, cap: "round"), 
    width: 100%, 
    radius: 2pt,
    block(
      inset: 1pt,
      width: 100%, 
      below: 0pt, 
      block(
        fill: background_color,
        width: 100%,
        inset: 8pt)[#if icon != none [#text(icon_color, weight: 900)[#icon] ]#title]) +
      if(body != []){
        block(
          inset: 1pt, 
          width: 100%, 
          block(fill: body_background_color, width: 100%, inset: 8pt, body))
      }
    )
}


// syntax highlighting functions from skylighting:
/* Function definitions for syntax highlighting generated by skylighting: */
#let EndLine() = raw("\n")
#let Skylighting(fill: none, number: false, start: 1, sourcelines) = {
   let blocks = []
   let lnum = start - 1
   let bgcolor = rgb("#24292e")
   for ln in sourcelines {
     if number {
       lnum = lnum + 1
       blocks = blocks + box(width: if start + sourcelines.len() > 999 { 30pt } else { 24pt }, text([ #lnum ]))
     }
     blocks = blocks + ln + EndLine()
   }
   block(fill: bgcolor, width: 100%, inset: 8pt, radius: 2pt, blocks)
}
#let AlertTok(s) = text(weight: "bold",fill: rgb("#ff5555"),raw(s))
#let AnnotationTok(s) = text(fill: rgb("#6a737d"),raw(s))
#let AttributeTok(s) = text(fill: rgb("#f97583"),raw(s))
#let BaseNTok(s) = text(fill: rgb("#79b8ff"),raw(s))
#let BuiltInTok(s) = text(fill: rgb("#f97583"),raw(s))
#let CharTok(s) = text(fill: rgb("#9ecbff"),raw(s))
#let CommentTok(s) = text(fill: rgb("#6a737d"),raw(s))
#let CommentVarTok(s) = text(fill: rgb("#6a737d"),raw(s))
#let ConstantTok(s) = text(fill: rgb("#79b8ff"),raw(s))
#let ControlFlowTok(s) = text(fill: rgb("#f97583"),raw(s))
#let DataTypeTok(s) = text(fill: rgb("#f97583"),raw(s))
#let DecValTok(s) = text(fill: rgb("#79b8ff"),raw(s))
#let DocumentationTok(s) = text(fill: rgb("#6a737d"),raw(s))
#let ErrorTok(s) = underline(text(fill: rgb("#ff5555"),raw(s)))
#let ExtensionTok(s) = text(weight: "bold",fill: rgb("#f97583"),raw(s))
#let FloatTok(s) = text(fill: rgb("#79b8ff"),raw(s))
#let FunctionTok(s) = text(fill: rgb("#b392f0"),raw(s))
#let ImportTok(s) = text(fill: rgb("#9ecbff"),raw(s))
#let InformationTok(s) = text(fill: rgb("#6a737d"),raw(s))
#let KeywordTok(s) = text(fill: rgb("#f97583"),raw(s))
#let NormalTok(s) = text(fill: rgb("#e1e4e8"),raw(s))
#let OperatorTok(s) = text(fill: rgb("#e1e4e8"),raw(s))
#let OtherTok(s) = text(fill: rgb("#b392f0"),raw(s))
#let PreprocessorTok(s) = text(fill: rgb("#f97583"),raw(s))
#let RegionMarkerTok(s) = text(fill: rgb("#6a737d"),raw(s))
#let SpecialCharTok(s) = text(fill: rgb("#79b8ff"),raw(s))
#let SpecialStringTok(s) = text(fill: rgb("#9ecbff"),raw(s))
#let StringTok(s) = text(fill: rgb("#9ecbff"),raw(s))
#let VariableTok(s) = text(fill: rgb("#ffab70"),raw(s))
#let VerbatimStringTok(s) = text(fill: rgb("#9ecbff"),raw(s))
#let WarningTok(s) = text(fill: rgb("#ff5555"),raw(s))



#let article(
  title: none,
  subtitle: none,
  authors: none,
  keywords: (),
  date: none,
  abstract-title: none,
  abstract: none,
  thanks: none,
  cols: 1,
  lang: "en",
  region: "US",
  font: none,
  fontsize: 11pt,
  title-size: 1.5em,
  subtitle-size: 1.25em,
  heading-family: none,
  heading-weight: "bold",
  heading-style: "normal",
  heading-color: black,
  heading-line-height: 0.65em,
  mathfont: none,
  codefont: none,
  linestretch: 1,
  sectionnumbering: none,
  linkcolor: none,
  citecolor: none,
  filecolor: none,
  toc: false,
  toc_title: none,
  toc_depth: none,
  toc_indent: 1.5em,
  doc,
) = {
  // Set document metadata for PDF accessibility
  set document(title: title, keywords: keywords)
  set document(
    author: authors.map(author => content-to-string(author.name)).join(", ", last: " & "),
  ) if authors != none and authors != ()
  set par(
    justify: true,
    leading: linestretch * 0.65em
  )
  set text(lang: lang,
           region: region,
           size: fontsize)
  set text(font: font) if font != none
  show math.equation: set text(font: mathfont) if mathfont != none
  show raw: set text(font: codefont) if codefont != none

  set heading(numbering: sectionnumbering)

  show link: set text(fill: rgb(content-to-string(linkcolor))) if linkcolor != none
  show ref: set text(fill: rgb(content-to-string(citecolor))) if citecolor != none
  show link: this => {
    if filecolor != none and type(this.dest) == label {
      text(this, fill: rgb(content-to-string(filecolor)))
    } else {
      text(this)
    }
   }

  let has-title-block = title != none or (authors != none and authors != ()) or date != none or abstract != none
  if has-title-block {
    place(
      top,
      float: true,
      scope: "parent",
      clearance: 4mm,
      block(below: 1em, width: 100%)[

        #if title != none {
          align(center, block(inset: 2em)[
            #set par(leading: heading-line-height) if heading-line-height != none
            #set text(font: heading-family) if heading-family != none
            #set text(weight: heading-weight)
            #set text(style: heading-style) if heading-style != "normal"
            #set text(fill: heading-color) if heading-color != black

            #text(size: title-size)[#title #if thanks != none {
              footnote(thanks, numbering: "*")
              counter(footnote).update(n => n - 1)
            }]
            #(if subtitle != none {
              parbreak()
              text(size: subtitle-size)[#subtitle]
            })
          ])
        }

        #if authors != none and authors != () {
          let count = authors.len()
          let ncols = calc.min(count, 3)
          grid(
            columns: (1fr,) * ncols,
            row-gutter: 1.5em,
            ..authors.map(author =>
                align(center)[
                  #author.name \
                  #author.affiliation \
                  #author.email
                ]
            )
          )
        }

        #if date != none {
          align(center)[#block(inset: 1em)[
            #date
          ]]
        }

        #if abstract != none {
          block(inset: 2em)[
          #text(weight: "semibold")[#abstract-title] #h(1em) #abstract
          ]
        }
      ]
    )
  }

  if toc {
    let title = if toc_title == none {
      auto
    } else {
      toc_title
    }
    block(above: 0em, below: 2em)[
    #outline(
      title: toc_title,
      depth: toc_depth,
      indent: toc_indent
    );
    ]
  }

  doc
}

#set table(
  inset: 6pt,
  stroke: none
)
#import "@preview/fontawesome:0.5.0": *
#let brand-color = (:)
#let brand-color-background = (:)
#let brand-logo = (:)

#set page(
  paper: "a4",
  margin: (x: 2.5cm,y: 2.5cm,),
  numbering: "1",
  columns: 1,
)

#show: doc => article(
  title: [Code Window],
  subtitle: [Quarto Extension],
  authors: (
    ( name: [Mickaël CANOUIL, #emph[Ph.D.]],
      affiliation: [],
      email: [] ),
    ),
  toc_title: [Table of contents],
  toc_depth: 3,
  doc,
)

// code-window: annotation state passed to Skylighting via Typst state
#let _cw-annotations = state("cw-annotations", none)

// Derive a contrasting annotation colour from a background fill.
// Light backgrounds get dark circles; dark backgrounds get light circles.
// Uses ITU-R BT.709 luminance coefficients, matching quarto-cli PR #14170.
#let code-window-annote-colour(bg) = {
  if type(bg) == color {
    let comps = bg.components(alpha: false)
    let lum = if comps.len() == 1 {
      comps.at(0) / 100%
    } else {
      0.2126 * comps.at(0) / 100% + 0.7152 * comps.at(1) / 100% + 0.0722 * comps.at(2) / 100%
    }
    if lum < 0.5 { luma(200) } else { luma(60) }
  } else {
    luma(60)
  }
}

#let code-window-circled-number(n, bg-colour: none) = {
  let c = if bg-colour != none { code-window-annote-colour(bg-colour) } else { luma(120) }
  box(baseline: 20%, circle(
    radius: 4.5pt,
    stroke: 0.5pt + c,
  )[#set text(size: 5.5pt, fill: c); #align(center + horizon, str(n))])
}

#let code-window-annotation-item(block-id, n, content) = {
  let lbl-prefix = "cw-" + str(block-id) + "-"
  [#block(above: 0.4em, below: 0.4em)[
    #link(label(lbl-prefix + "line-" + str(n)))[
      #code-window-circled-number(n)
    ]
    #h(0.4em)
    #content
  ] #label(lbl-prefix + "item-" + str(n))]
}

#let code-window-annotated-content(content, annotations: (:), bg-colour: none, block-id: 0) = {
  if annotations.len() > 0 {
    _cw-annotations.update((annotations: annotations, bg-colour: bg-colour, block-id: block-id))
    content
    _cw-annotations.update(none)
  } else {
    content
  }
}
#let code-window(
  content,
  filename: none,
  is-auto: false,
  style: "macos",
  annotations: (:),
  bg-colour: none,
  block-id: 0,
) = {
  let border-colour = luma(200)
  let surface-fill = luma(237)
  let muted-colour = luma(120)

  let filename-label = if filename != none {
    text(
      size: if is-auto { 0.7em } else { 0.85em },
      weight: 500,
      fill: muted-colour,
      if is-auto { upper(filename) } else { filename },
    )
  }

  let traffic-lights = box(
    inset: (right: 0.5em),
    stack(
      dir: ltr,
      spacing: 0.425em,
      circle(radius: 0.425em, fill: rgb("#ff5f56"), stroke: none),
      circle(radius: 0.425em, fill: rgb("#ffbd2e"), stroke: none),
      circle(radius: 0.425em, fill: rgb("#27c93f"), stroke: none),
    ),
  )

  let window-buttons = box(
    inset: (left: 0.5em),
    {
      set line(stroke: 1pt + muted-colour)
      stack(
        dir: ltr,
        spacing: 0.8em,
        // Minimise (horizontal line)
        box(width: 0.6em, height: 0.6em, align(horizon, line(length: 100%))),
        // Maximise (square)
        box(width: 0.6em, height: 0.6em, stroke: 1pt + muted-colour),
        // Close (x)
        box(width: 0.6em, height: 0.6em, {
          place(line(start: (0%, 0%), end: (100%, 100%)))
          place(line(start: (100%, 0%), end: (0%, 100%)))
        }),
      )
    },
  )

  let title-bar = if style == "macos" {
    grid(
      columns: (auto, 1fr),
      align: (left + horizon, right + horizon),
      gutter: 0.5em,
      stroke: 0pt,
      traffic-lights,
      filename-label,
    )
  } else if style == "windows" {
    grid(
      columns: (1fr, auto),
      align: (left + horizon, right + horizon),
      gutter: 0.5em,
      stroke: 0pt,
      filename-label,
      window-buttons,
    )
  } else {
    // default: plain filename, left-aligned
    filename-label
  }

  block(
    width: 100%,
    stroke: 1pt + border-colour,
    radius: 8pt,
    clip: true,
    {
      block(
        width: 100%,
        fill: surface-fill,
        inset: (x: 1em, y: 0.6em),
        below: 0pt,
        radius: 0pt,
        stroke: (bottom: 1pt + border-colour),
        sticky: true,
        title-bar,
      )
      // Strip code block chrome so content fills flush against the window body.
      // set block() provides defaults for Skylighting blocks (explicit fill preserved).
      // show raw overrides the document-level raw block styling (fill, radius).
      {
        set block(
          width: 100%,
          inset: 8pt,
          radius: 0pt,
          stroke: none,
          above: 0pt,
          below: 0pt,
        )
        show raw.where(block: true): set block(
          fill: none,
          width: 100%,
          radius: 0pt,
          stroke: none,
          above: 0pt,
          below: 0pt,
        )
        code-window-annotated-content(
          content,
          annotations: annotations,
          bg-colour: bg-colour,
          block-id: block-id,
        )
      }
    },
  )
}
// skylighting-typst-fix override
#let Skylighting(
  fill: none,
  number: false,
  start: 1,
  sourcelines,
) = {
  let bgcolor = if fill != none { fill } else { rgb("#24292e") }
  let has-gutter = start + sourcelines.len() > 999

  context {
    let annot-data = _cw-annotations.get()
    let blocks = []
    let lnum = start - 1
    let seen-annotes = (:)

    for ln in sourcelines {
      lnum = lnum + 1
      if number {
        blocks = blocks + box(
          width: if has-gutter { 30pt } else { 24pt },
          text([ #lnum ]),
        )
      }

      if annot-data != none {
        let annot-num = annot-data.annotations.at(str(lnum), default: none)
        if annot-num != none {
          let lbl-prefix = "cw-" + str(annot-data.block-id) + "-"
          if str(annot-num) not in seen-annotes {
            seen-annotes.insert(str(annot-num), true)
            blocks = blocks + box(width: 100%)[
              #ln
              #h(1fr)
              #link(label(lbl-prefix + "item-" + str(annot-num)))[
                #code-window-circled-number(annot-num, bg-colour: annot-data.bg-colour)
              ]
              #label(lbl-prefix + "line-" + str(annot-num))
            ]
          } else {
            blocks = blocks + box(width: 100%)[
              #ln
              #h(1fr)
              #link(label(lbl-prefix + "item-" + str(annot-num)))[
                #code-window-circled-number(annot-num, bg-colour: annot-data.bg-colour)
              ]
            ]
          }
        } else {
          blocks = blocks + ln
        }
      } else {
        blocks = blocks + ln
      }
      blocks = blocks + EndLine()
    }

    block(
      fill: bgcolor,
      width: 100%,
      inset: 8pt,
      radius: 2pt,
      stroke: 0.5pt + luma(200),
      blocks,
    )
  }
}
= Explicit Filename
<explicit-filename>
Code blocks with a #box(fill: rgb("#24292e"), inset: (x: 3pt, y: 0pt), outset: (y: 3pt), radius: 2pt, stroke: none)[#NormalTok("filename");] attribute display a window header with the filename. The decoration style depends on the #box(fill: rgb("#24292e"), inset: (x: 3pt, y: 0pt), outset: (y: 3pt), radius: 2pt, stroke: none)[#NormalTok("style");] option (default: #box(fill: rgb("#24292e"), inset: (x: 3pt, y: 0pt), outset: (y: 3pt), radius: 2pt, stroke: none)[#NormalTok("\"macos\"");]).

#code-window(filename: "fibonacci.py", is-auto: false, style: "macos", bg-colour: rgb("#24292e"))[
#Skylighting(([#KeywordTok("def");#NormalTok(" fibonacci(n: ");#BuiltInTok("int");#NormalTok(") ");#OperatorTok("->");#NormalTok(" ");#BuiltInTok("int");#NormalTok(":");],
[#NormalTok("    ");#CommentTok("\"\"\"Calculate the nth Fibonacci number.\"\"\"");],
[#NormalTok("    ");#ControlFlowTok("if");#NormalTok(" n ");#OperatorTok("<=");#NormalTok(" ");#DecValTok("1");#NormalTok(":");],
[#NormalTok("        ");#ControlFlowTok("return");#NormalTok(" n");],
[#NormalTok("    ");#ControlFlowTok("return");#NormalTok(" fibonacci(n ");#OperatorTok("-");#NormalTok(" ");#DecValTok("1");#NormalTok(") ");#OperatorTok("+");#NormalTok(" fibonacci(n ");#OperatorTok("-");#NormalTok(" ");#DecValTok("2");#NormalTok(")");],));
]
#code-window(filename: "analysis.R", is-auto: false, style: "macos", bg-colour: rgb("#24292e"))[
#Skylighting(([#CommentTok("# Load data and create summary");],
[#NormalTok("data ");#OtherTok("<-");#NormalTok(" ");#FunctionTok("read.csv");#NormalTok("(");#StringTok("\"data.csv\"");#NormalTok(")");],
[#FunctionTok("summary");#NormalTok("(data)");],));
]
= Auto-Generated Filename
<auto-generated-filename>
With #box(fill: rgb("#24292e"), inset: (x: 3pt, y: 0pt), outset: (y: 3pt), radius: 2pt, stroke: none)[#NormalTok("auto-filename: true");] (the default), code blocks without explicit filenames automatically show the language name in small-caps styling.

#code-window(filename: "python", is-auto: true, style: "macos", bg-colour: rgb("#24292e"))[
#Skylighting(([#KeywordTok("def");#NormalTok(" greet(name: ");#BuiltInTok("str");#NormalTok(") ");#OperatorTok("->");#NormalTok(" ");#BuiltInTok("str");#NormalTok(":");],
[#NormalTok("    ");#CommentTok("\"\"\"Return a greeting message.\"\"\"");],
[#NormalTok("    ");#ControlFlowTok("return");#NormalTok(" ");#SpecialStringTok("f\"Hello, ");#SpecialCharTok("{");#NormalTok("name");#SpecialCharTok("}");#SpecialStringTok("!\"");],));
]
#code-window(filename: "r", is-auto: true, style: "macos", bg-colour: rgb("#24292e"))[
#Skylighting(([#CommentTok("# Create sample data");],
[#NormalTok("data ");#OtherTok("<-");#NormalTok(" ");#FunctionTok("data.frame");#NormalTok("(");],
[#NormalTok("  ");#AttributeTok("x =");#NormalTok(" ");#DecValTok("1");#SpecialCharTok(":");#DecValTok("10");#NormalTok(",");],
[#NormalTok("  ");#AttributeTok("y =");#NormalTok(" ");#FunctionTok("rnorm");#NormalTok("(");#DecValTok("10");#NormalTok(")");],
[#NormalTok(")");],
[#FunctionTok("summary");#NormalTok("(data)");],));
]
#code-window(filename: "bash", is-auto: true, style: "macos", bg-colour: rgb("#24292e"))[
#Skylighting(([#CommentTok("#!/bin/bash");],
[#BuiltInTok("echo");#NormalTok(" ");#StringTok("\"Hello, World!\"");],));
]
= Plain Code Block
<plain-code-block>
Code blocks without a language are not affected by the extension.

#Skylighting(([#NormalTok("This is a plain code block without any language specified.");],
[#NormalTok("No window decoration is applied here.");],));
= Disabled Auto-Filename
<disabled-auto-filename>
To disable auto-generated filenames, set #box(fill: rgb("#24292e"), inset: (x: 3pt, y: 0pt), outset: (y: 3pt), radius: 2pt, stroke: none)[#NormalTok("auto-filename: false");] in the extension configuration. Only code blocks with an explicit #box(fill: rgb("#24292e"), inset: (x: 3pt, y: 0pt), outset: (y: 3pt), radius: 2pt, stroke: none)[#NormalTok("filename");] attribute will display window decorations.

= Window Styles
<window-styles>
Three decoration styles are available via the #box(fill: rgb("#24292e"), inset: (x: 3pt, y: 0pt), outset: (y: 3pt), radius: 2pt, stroke: none)[#NormalTok("style");] option. The global style can be set in the document configuration. Individual blocks can override the style with the #box(fill: rgb("#24292e"), inset: (x: 3pt, y: 0pt), outset: (y: 3pt), radius: 2pt, stroke: none)[#NormalTok("code-window-style");] attribute.

== macOS Style (default)
<macos-style-default>
Traffic light buttons on the left, filename on the right.

#code-window(filename: "macos-example.py", is-auto: false, style: "macos", bg-colour: rgb("#24292e"))[
#Skylighting(([#BuiltInTok("print");#NormalTok("(");#StringTok("\"macOS style window\"");#NormalTok(")");],));
]
== Windows Style
<windows-style>
Minimise, maximise, and close buttons on the right, filename on the left.

#code-window(filename: "windows-example.py", is-auto: false, style: "windows", bg-colour: rgb("#24292e"))[
#Skylighting(([#BuiltInTok("print");#NormalTok("(");#StringTok("\"Windows style window\"");#NormalTok(")");],));
]
== Default Style
<default-style>
Plain filename on the left, no window decorations.

#code-window(filename: "default-example.py", is-auto: false, style: "default", bg-colour: rgb("#24292e"))[
#Skylighting(([#BuiltInTok("print");#NormalTok("(");#StringTok("\"Default style window\"");#NormalTok(")");],));
]
= Code Annotations
<code-annotations>
#block[
#callout(
body: 
[
Typst code-annotations support and #box(fill: rgb("#24292e"), inset: (x: 3pt, y: 0pt), outset: (y: 3pt), radius: 2pt, stroke: none)[#NormalTok("filename");] attribute handling are temporary hot-fixes. They will be removed once Quarto natively supports these features (see #link("https://github.com/quarto-dev/quarto-cli/pull/14170")[quarto-dev/quarto-cli\#14170]). The extension will then focus on #strong[auto-filename] and #strong[code-window-style] features.

]
, 
title: 
[
Note
]
, 
background_color: 
rgb("#dae6fb")
, 
icon_color: 
rgb("#0758E5")
, 
icon: 
fa-info()
, 
body_background_color: 
white
)
]
Code annotations work standalone and together with code-window styling.

== Annotations with Explicit Filename
<annotations-with-explicit-filename>
#code-window(filename: "annotated.py", is-auto: false, style: "macos", annotations: ("1": 1, "3": 2, "4": 3), block-id: 1, bg-colour: rgb("#24292e"))[
#Skylighting(([#ImportTok("import");#NormalTok(" pandas ");#ImportTok("as");#NormalTok(" pd");],
[],
[#NormalTok("df ");#OperatorTok("=");#NormalTok(" pd.read_csv(");#StringTok("\"data.csv\"");#NormalTok(")");],
[#NormalTok("summary ");#OperatorTok("=");#NormalTok(" df.describe()");],));
]
#code-window-annotation-item(1, 1)[Import the pandas library.]
#code-window-annotation-item(1, 2)[Load data from a CSV file.]
#code-window-annotation-item(1, 3)[Generate summary statistics.]
== Annotations with Auto-Filename
<annotations-with-auto-filename>
#code-window(filename: "python", is-auto: true, style: "macos", annotations: ("1": 1, "2": 2, "4": 3), block-id: 2, bg-colour: rgb("#24292e"))[
#Skylighting(([#KeywordTok("def");#NormalTok(" greet(name: ");#BuiltInTok("str");#NormalTok(") ");#OperatorTok("->");#NormalTok(" ");#BuiltInTok("str");#NormalTok(":");],
[#NormalTok("    ");#ControlFlowTok("return");#NormalTok(" ");#SpecialStringTok("f\"Hello, ");#SpecialCharTok("{");#NormalTok("name");#SpecialCharTok("}");#SpecialStringTok("!\"");],
[],
[#NormalTok("result ");#OperatorTok("=");#NormalTok(" greet(");#StringTok("\"World\"");#NormalTok(")");],));
]
#code-window-annotation-item(2, 1)[Define a function with type hints.]
#code-window-annotation-item(2, 2)[Use an f-string for interpolation.]
#code-window-annotation-item(2, 3)[Call the function and store the result.]
== Annotations Spanning Multiple Lines
<annotations-spanning-multiple-lines>
A single annotation number can appear on several consecutive lines. Only the first occurrence receives a back-label to avoid duplicates.

#code-window(filename: "pipeline.py", is-auto: false, style: "macos", annotations: ("1": 1, "2": 1, "3": 1, "4": 2, "5": 3), block-id: 3, bg-colour: rgb("#24292e"))[
#Skylighting(([#KeywordTok("def");#NormalTok(" process(data):");],
[#NormalTok("    cleaned ");#OperatorTok("=");#NormalTok(" clean(data)");],
[#NormalTok("    validated ");#OperatorTok("=");#NormalTok(" validate(cleaned)");],
[#NormalTok("    result ");#OperatorTok("=");#NormalTok(" transform(validated)");],
[#NormalTok("    ");#ControlFlowTok("return");#NormalTok(" result");],));
]
#code-window-annotation-item(3, 1)[Multi-step input preparation (cleaning and validation).]
#code-window-annotation-item(3, 2)[Apply the main transformation.]
#code-window-annotation-item(3, 3)[Return the final result.]
== Annotations without Window Chrome
<annotations-without-window-chrome>
Set #box(fill: rgb("#24292e"), inset: (x: 3pt, y: 0pt), outset: (y: 3pt), radius: 2pt, stroke: none)[#NormalTok("code-window-enabled=\"false\"");] on a block to disable window chrome while keeping annotations.

#code-window-annotated-content(annotations: ("1": 1, "2": 2, "3": 3, "4": 4), block-id: 4, bg-colour: rgb("#24292e"))[
#Skylighting(([#FunctionTok("library");#NormalTok("(ggplot2)");],
[#FunctionTok("ggplot");#NormalTok("(mtcars) ");#SpecialCharTok("+");],
[#NormalTok("  ");#FunctionTok("aes");#NormalTok("(");#AttributeTok("x =");#NormalTok(" mpg, ");#AttributeTok("y =");#NormalTok(" hp) ");#SpecialCharTok("+");],
[#NormalTok("  ");#FunctionTok("geom_point");#NormalTok("()");],));
]
#code-window-annotation-item(4, 1)[Load the ggplot2 package.]
#code-window-annotation-item(4, 2)[Initialise a plot with the mtcars dataset.]
#code-window-annotation-item(4, 3)[Map aesthetics.]
#code-window-annotation-item(4, 4)[Add a point geometry layer.]
== Configuration
<configuration>
Set the global style in the document front matter:

#code-window(filename: "yaml", is-auto: true, style: "macos", bg-colour: rgb("#24292e"))[
#Skylighting(([#FunctionTok("extensions");#KeywordTok(":");],
[#AttributeTok("  ");#FunctionTok("code-window");#KeywordTok(":");],
[#AttributeTok("    ");#FunctionTok("style");#KeywordTok(":");#AttributeTok(" ");#StringTok("\"macos\"");],
[#AttributeTok("    ");#FunctionTok("hotfix");#KeywordTok(":");],
[#AttributeTok("      ");#FunctionTok("quarto-version");#KeywordTok(":");#AttributeTok(" ");#CharTok("~");],
[#AttributeTok("      ");#FunctionTok("code-annotations");#KeywordTok(":");#AttributeTok(" ");#CharTok("true");],
[#AttributeTok("      ");#FunctionTok("skylighting");#KeywordTok(":");#AttributeTok(" ");#CharTok("true");],));
]
Override per block with the #box(fill: rgb("#24292e"), inset: (x: 3pt, y: 0pt), outset: (y: 3pt), radius: 2pt, stroke: none)[#NormalTok("code-window-style");] attribute:

#code-window(filename: "markdown", is-auto: true, style: "macos", bg-colour: rgb("#24292e"))[
#Skylighting(([#InformationTok("```{.python filename=\"example.py\" code-window-style=\"windows\"}");],
[#BuiltInTok("print");#NormalTok("(");#StringTok("\"Windows style for this block only\"");#NormalTok(")");],
[#InformationTok("```");],));
]



