# KFIndexBar

A zoomable index bar for use with `UICollectionView` or similar.

## Overview

*KFIndexBar* is a control which may be placed over the side of a collection view. It may be used to give a swipeable index, allowing the user to quickly scroll the collection view to any section by touching, say, the initial letter of an alphabetically sorted list. (The contents of the index bar are completely configurable.) Unlike the `UITableView`'s built-in index, `KFIndexBar` may be either horizontal (running along the bottom of the view) or vertical (along the right). Also, `KFIndexBar` allows the index to have two levels, with the user dragging left (on a vertical bar; or up, on a horizontal bar) to open the second level of markers between two markers. For example, in an alphabetical index bar, touching the label for "A" and dragging left might open a set of secondary labels reading "AA", "AD", "AF", and so on; once opened, dragging over these will scroll to the relevant location.

## Using KFIndexBar

To place in your interface, add to your `UICollectionView`'s parent view, above the collection view, and use constraints to attach to the appropriate side of the screen. Be sure to set `KFIndexBar`'s `isHorizontal` variable to indicate its orientation. (Horizontal index bars, running along the bottom of the screen, are recommended for horizontally-scrolling collection views.)

`KFIndexBar` defines a protocol named `KFIndexBarDataSource`, which your code needs to implement to populate the bar with markers. Each marker is represented by a structure, `KFIndexBar.Marker`, which contains the label text to display and an offset in the data to scroll to. The `KFIndexBarDataSource` specifies two methods you need to implement, which are:

 * `topLevelMarkers(forIndexBar:)` — return a list of the markers which will be seen in the initial, not zoomed-in state. In an example in alphabetical order, these would have the labels 'A', 'B' and so on, each with an offset pointing to the index of the data item to scroll to.
 * `indexBar(: markersBetween: and: Int)` - this returns second-level markers when the user zooms in between two markers. It should return all the second-level markers from the first offset to just before the second offset (which may be infinity, if the user is zooming in below the last top-level marker). If there are no second-level markers, return an empty array.

`KFIndexBar` is a `UIControl`, and sends a `valueChanged` UIControl event when the offset it points to has changed. This offset may be read from its `currentOffset` instance variable.

An example, allowing the user to navigate an alphabetical list (populated with over 1,100 surnames), is included in this repository.

## Compatibility

KFIndexBar is written in Swift 4. Due to its use of Swift's type system, it probably won't ever be compatible with Objective C, but if you're writing new code in Objective C, you should probably ask yourself why.

## Limitations

KFIndexBar currently assumes that the data being scrolled over is in one section, with an integer index; multi-part `IndexPath`s are not yet supported, though may be added in future.

## Tests

The example project contains unit tests for `KFIndexBar`'s internal layout logic.

## Authors

 * **Andrew Bulhak** - *initial development* - [GitHub](https://github.com/andrewcb/)/[Technical blog](http://tech.null.org/)

## License

`KFIndexBar` is licenced under the MIT License
