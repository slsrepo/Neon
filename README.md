<div align="center">

[![Build Status][build status badge]][build status]
[![Platforms][platforms badge]][platforms]
[![Documentation][documentation badge]][documentation]

</div>

# Neon
A Swift library for efficient, flexible content-based text styling.

- Lazy content processing
- Minimal invalidation calculation
- Support for up to three-phase highlighting via fallback, primary, and secondary sources
- Support for versionable text data storage
- A hybrid sync/async system for targeting flicker-free styling on keystrokes
- [tree-sitter](https://tree-sitter.github.io/tree-sitter/) integration
- Text-system agnostic

Neon has a strong focus on efficiency and flexibility. It sits in-between your text system and wherever you get your semantic token information. Neon was developed for syntax highlighting and it can serve that need very well. However, it is more general-purpose than that and could be used for any system that needs to manage the state of range-based content.

Many people are looking for a drop-in editor View subclass that does it all. This is a lower-level library. You could, however, use Neon to drive highlighting for a view like this.

> [!NOTE]
> The code on the main branch is still not quite ready for release. But, all documentation and development effort is there, and it should be considered very usable.

## Installation

```swift
dependencies: [
    .package(url: "https://github.com/ChimeHQ/Neon", branch: "main")
],
targets: [
    .target(
        name: "MyTarget",
        dependencies: [
            "Neon",
            .product(name: "TreeSitterClient", package: "Neon"),
            .product(name: "RangeState", package: "Neon"),
        ]
    ),
]
```

## Concepts

Neon is made up of three parts: the core library, `RangeState` and `TreeSitterClient`.

### RangeState

Neon's lowest-level component is called RangeState. This module contains the core building blocks used for the rest of the system. RangeState is built around the idea of hybrid synchronous/asynchronous execution. Making everything async would be a lot easier, but would make it impossible to provide a low-latency path for small documents. RangeState is content-independent.

- `HybridSyncAsyncValueProvider`: a fundamental type that defines work in terms of both synchronous and asynchronous functions
- `RangeProcessor`: performs on-demand processing of range-based content (think parsing)
- `RangeValidator`: building block for managing the validation of range-based content
- `RangeInvalidationBuffer`: buffers and consolidates invalidations so they can be applied at the optimal time
- `SinglePhaseRangeValidator`: performs validation with a single data source (single-phase highlighting)
- `ThreePhaseRangeValidator`: performs validation with primary, fallback, and secondary data sources (three-phase highlighting)

Many of these support versionable content. If you are working with a backing store structure that supports efficient versioning, like a [piece table](https://en.wikipedia.org/wiki/Piece_table), expressing this to RangeState can improve its efficiency.

### Neon

The top-level module includes systems for managing text styling. It is also text-system independent. It makes very few assumptions about how text is stored, displayed, or styled. It also includes some components for use with stock AppKit and UIKit systems. These are provided for easy integration, not maximum performance. 

- `TextViewHighlighter`: simple integration between `NSTextView`/`UITextView` and `TreeSitterClient`
- `TextViewSystemInterface`: implementation of the `TextSystemInterface` protocol for `NSTextView`/`UITextView`
- `LayoutManagerSystemInterface`, `TextLayoutManagerSystemInterface`, and `TextStorageSystemInterface`: Specialized TextKit 1/2 implementations `TextSystemInterface`
- `TextSystemStyler`: a style manager that works with a single `TokenProvider`
- `ThreePhaseTextSystemStyler`: a true three-phase style manager that combines a primary, fallback and secondary token data sources

There is also an [example project](/Projects/) that demonstrates how to use `TextViewHighlighter` for macOS and iOS.

#### TextKit Integration

In a traditional `NSTextStorage`-backed system (TextKit 1 and 2), it can be challenging to achieve flicker-free on-keypress highlighting. You need to know when a text change has been processed by enough of the system that styling is possible. This point in the text change lifecycle is not natively supported by `NSTextStorage` or `NSLayoutManager`. It requires an `NSTextStorage` subclass. Such a subclass, `TSYTextStorage` is available in [TextStory](https://github.com/ChimeHQ/TextStory).

But, even that isn't quite enough unfortunately. You still need to precisely control the timing of invalidation and styling. This is where `RangeInvalidationBuffer` comes in.

I have not yet figured out a way to do this with TextKit 2, and it may not be possible without new API.

#### Performance

Neon's performance is highly dependant on the text system integration. Every aspect is important as there are performance cliffs all around. But, priority range calculations (the visible set for most text views) are of particular importance. This is surprisingly challenging to do correctly with TextKit 1, and extremely hard with TextKit 2.

Bottom line: Neon is extremely efficient. The bottlenecks will probably be your parsing system and text view. It can do a decent job of hiding parsing performance issues too. However, that doesn't mean it's perfect. There's always room for improvement and if you suspect a problem please do file an issue.

### TreeSitterClient

This library is a hybrid sync/async interface to [SwiftTreeSitter][SwiftTreeSitter]. It features:

- UTF-16 code-point (`NSString`-compatible) API for edits, invalidations, and queries
- Processing edits of `String` objects, or raw bytes
- Invalidation translation to the current content state regardless of background processing
- On-demand nested language resolution via tree-sitter's injection system
- Background processing when needed to scale to large documents

Tree-sitter uses separate compiled parsers for each language. There are a variety of ways to use tree-sitter parsers with SwiftTreeSitter. Check out that project for details.

### Token Data Sources

Neon was designed to accept and overlay token data from multiple sources simultaneously. Here's a real-world example of how this is used:

- First pass: pattern-matching system with ok quality and guaranteed low-latency
- Second pass: [tree-sitter](https://tree-sitter.github.io/tree-sitter/), which has good quality and **could** be low-latency
- Third pass: [Language Server Protocol](https://microsoft.github.io/language-server-protocol/)'s [semantic tokens](https://microsoft.github.io/language-server-protocol/specifications/specification-current/#textDocument_semanticTokens), which can augment existing highlighting, but is high-latency

An example of a first-pass system you might be interested in is [Lowlight](https://github.com/ChimeHQ/Lowlight).

### Theming

A highlighting theme is really just a mapping from semantic labels to styles. Token data sources apply the semantic labels and the `TextSystemInterface` uses those labels to look up styling.

This separation makes it very easy for you to do this look-up in a way that makes the most sense for whatever theming formats you'd like to support. This is also a convenient spot to adapt/modify the semantic labels coming from your data sources into a normalized form.

If you are looking for some help here, check out [ThemePark](https://github.com/ChimeHQ/ThemePark).

## Usage

### TreeSitterClient

Here's a minimal sample using TreeSitterClient. It is involved, but should give you an idea of what needs to be done.

```swift
import Neon
import SwiftTreeSitter
import TreeSitterClient

import TreeSitterSwift // this parser is available via SPM (see SwiftTreeSitter's README.md)

// assume we have a text view available that has been loaded with some Swift source

let languageConfig = try LanguageConfiguration(
    tree_sitter_swift(),
    name: "Swift"
)

let clientConfig = TreeSitterClient.Configuration(
    languageProvider: { identifier in
        // look up nested languages by identifier here. If done
        // asynchronously, inform the client they are ready with
        // `languageConfigurationChanged(for:)`
        return nil
    },
    contentSnapshotProvider: { [textView] length in
        // given a maximum needed length, produce a `ContentSnapshot` structure
        // that will be used to access immutable text data

        // this can work for any system that efficiently produce a `String`
        return .init(string: textView.string)
    },
    lengthProvider: { [textView] in
        textView.string.utf16.count
    },
    invalidationHandler: { set in
        // take action on invalidated regions of the text
    },
    locationTransformer: { location in
        // optionally, use the UTF-16 location to produce a line-relative Point structure.
        return nil
    }
)

let client = try TreeSitterClient(
    rootLanguageConfig: languageConfig,
    configuration: clientConfig
)

let source = textView.string

let provider = source.predicateTextProvider

// this uses the synchronous query API, but with the `.required` mode, which will force the client
// to do all processing necessary to satisfy the request.
let highlights = try client.highlights(in: NSRange(0..<24), provider: provider, mode: .required)!

print("highlights:", highlights)
```

TreeSitterClient can also perform static highlighting. This can be handy for applying style to a string.

```swift
let languageConfig = try LanguageConfiguration(
    tree_sitter_swift(),
    name: "Swift"
)

let attrProvider: TokenAttributeProvider = { token in
    return [.foregroundColor: NSColor.red]
}

// produce an AttributedString
let highlightedSource = try await TreeSitterClient.highlight(
    string: source,
    attributeProvider: attrProvider,
    rootLanguageConfig: languageConfig,
    languageProvider: { _ in nil }
)
```

## Contribution and Collaboration

I would love to hear from you! Issues or pull requests work great.

I prefer collaboration, and would love to find ways to work together if you have a similar project.

I prefer indentation with tabs for improved accessibility. But, I'd rather you use the system you want and make a PR than hesitate because of whitespace.

By participating in this project you agree to abide by the [Contributor Code of Conduct](CODE_OF_CONDUCT.md).

[build status]: https://github.com/ChimeHQ/Neon/actions
[build status badge]: https://github.com/ChimeHQ/Neon/workflows/CI/badge.svg
[platforms]: https://swiftpackageindex.com/ChimeHQ/Neon
[platforms badge]: https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2FChimeHQ%2FNeon%2Fbadge%3Ftype%3Dplatforms
[documentation]: https://swiftpackageindex.com/ChimeHQ/Neon/main/documentation
[documentation badge]: https://img.shields.io/badge/Documentation-DocC-blue
[SwiftTreeSitter]: https://github.com/ChimeHQ/SwiftTreeSitter
