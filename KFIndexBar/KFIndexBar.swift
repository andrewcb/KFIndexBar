//
//  KFIndexBar.swift
//  KFIndexBarExample
//
//  Created by acb on 29/08/2017.
//  Copyright © 2017 Kineticfactory. All rights reserved.
//

import UIKit

protocol KFIndexBarDataSource {
    /** Return the markers shown in the zoomed-out state. */
    func topLevelMarkers(forIndexBar: KFIndexBar) -> [KFIndexBar.Marker]
    
    /** Return a list of all the second-level markers between two points */
    func indexBar(_ indexBar: KFIndexBar, markersBetween start: Int, and end: Int) -> [KFIndexBar.Marker]
}

class KFIndexBar: UIControl {
    
    /** A Marker represents a label on the index bar, and the offset it points to. */
    struct Marker : KFIndexBarMarkerProtocol {
        /** The text displayed on the index bar; typically 1-2 characters long. */
        let label: String
        /** The offset into the list of displayed items that the label points to. */
        let offset: Int
    }
    
    /** The source of marker data; KFIndexBar will query this when `reloadData()` is called, and when the user zooms in. */
    var dataSource: KFIndexBarDataSource? = nil
    
    /** The offset in the list of displayed items of the parent collection view that the last selected label on the index bar points to. */
    var currentOffset: Int { return self._currentOffset }
    
    private var _currentOffset: Int = 0 {
        didSet(oldValue) {
            if self._currentOffset != oldValue {
                self.sendActions(for: .valueChanged)
            }
        }
    }
    
    // An object modelling the placement of labels on a line, and the zooming from an outer set of labels to an inner one
    struct LineModel {
        
        // A `Line` is an individual line of items, with a length. It is given a list of sizes and a delta value to shift positions by and, from this, calculates item midpoints and global values (such as the start and end of all items, the total span occupied by items, and the global midpoint of this span).
        struct Line {
            var length: CGFloat { didSet { self.recalculate() } }
            let margin: CGFloat

            var itemSizes: [CGFloat]? = nil { didSet { self.recalculate() } }
            /// The displacement value added to all points
            var delta: CGFloat = 0.0 {
                didSet {
                    self.recalculate()
                }
            }

            // derived values
            var midpoints: [CGFloat]? = nil
            /// the point at which the first item starts
            var startPos: CGFloat?
            /// the point at which the last item ends
            var endPos: CGFloat?
            /// the space taken up between startPos and endPos
            var extent: CGFloat = 0.0
            /// the point equidistant between startPos and endPos
            var midpoint: CGFloat?
            /// the gap between items; usualy equal to margin, unless shrunk
            var itemGap: CGFloat = 0.0

            init(length: CGFloat, margin: CGFloat) {
                self.length = length
                self.margin = margin
            }
            
            mutating func setSizes(_ sizes: [CGFloat]) {
                self.itemSizes = sizes
            }
            
            /** Calculate the offset to adjust positions by, which is as close to being centred around `zoomOrigin` as possible without the outermost elements going out of the line's space */
            mutating func calculateDelta(forZoomOrigin zoomOrigin: CGFloat) {
                let centre = self.length * 0.5
                let rawΔ = zoomOrigin - centre
                let sizes = self.itemSizes ?? []
                let halfSize = (sizes.isEmpty ? 0.0 : sizes.reduce(0,+) + (CGFloat(sizes.count-1)*self.itemGap)) * 0.5
                if rawΔ < 0.0 {
                    let top = centre - halfSize
                    self.delta = max(0.0, top+rawΔ) - top
                } else {
                    let bottom = centre + halfSize
                    self.delta = min(length, bottom+rawΔ) - bottom
                }
            }
            
            mutating func recalculate() {
                guard let sizes = self.itemSizes, sizes.count >= 2 else {
                    self.midpoints = self.itemSizes.map { $0.map { _ in (self.length * 0.5)+self.delta} }
                    self.itemGap = self.margin
                    self.startPos = (self.itemSizes?.first.map { (self.length - $0) * 0.5 } ?? 0.0) + delta
                    self.endPos = (self.itemSizes?.first.map { (self.length + $0) * 0.5 } ?? 0.0)  + delta
                    self.extent = self.itemSizes?.first ?? 0.0
                    self.midpoint = self.length * 0.5 + delta
                    return
                }
                let totalSize =  sizes.reduce(0,+)
                self.itemGap = min(margin, (self.length - totalSize) / CGFloat(sizes.count - 1))
                self.startPos = ((self.length - (totalSize + CGFloat(sizes.count-1) * itemGap)) * 0.5) + self.delta
                self.midpoints = (sizes.reduce(([], startPos!)) {  (acc:([CGFloat],CGFloat), size:CGFloat) in
                    (acc.0 + [acc.1+size*0.5], acc.1+size+itemGap)
                }).0
                self.endPos = midpoints?.last.flatMap { (mp) in self.itemSizes?.last.flatMap { (sz) in mp + sz*0.5 } }
                self.extent = self.endPos! - self.startPos!
                self.midpoint = (self.endPos! + self.startPos!) * 0.5
            }
            
            func midpointsScaled(by factor: CGFloat, from origin: CGFloat) -> [CGFloat] {
                return (self.midpoints ?? []).map { (($0 - origin) * factor) + origin }
            }
            
            func trailingBoundary(after index: Int) -> CGFloat {
                guard let midpoints = self.midpoints, let sizes = self.itemSizes else { return self.length * 0.5 }
                if index < midpoints.count-1 {
                    let thisEnd = midpoints[index]+sizes[index]*0.5
                    let nextStart = midpoints[index+1] - sizes[index+1]*0.5
                    return (thisEnd + nextStart) * 0.5
                } else {
                    return self.length - 1.0
                }
            }
            
            func midpointGap(after index: Int) -> CGFloat {
                guard let midpoints = self.midpoints, index < midpoints.count else { return 0.0 }
                let pos0 = midpoints[index]
                let pos1 = (index >= midpoints.count-1) ? self.length : midpoints[index+1]
                return pos1 - pos0
            }

            func findItem(forPosition pos: CGFloat) -> Int? {
                guard
                    let midpoints = self.midpoints,
                    !midpoints.isEmpty,
                    let sizes = self.itemSizes,
                    let startPos = self.startPos,
                    let endPos = self.endPos,
                    pos >= startPos,
                    pos <= endPos
                    else { return nil }
                return (zip(midpoints, sizes).enumerated().first { ($0.element.0 - ($0.element.1*0.5)) >= pos }?.offset).map { $0 - 1 }.flatMap { $0>=0 ? $0 : nil } ?? (midpoints.count-1)
            }
        }
        
        // the `LineModel` maintains two `Line`s: one representing the outer markers, in their normal, zoomed-out state, and one representing the inner markers, when fully zoomed in (whose values are only valid when a zooming operation is taking place, as the markers will vary). Interpolating between these two is the `LineModel`'s responsibility.
        var outer0: Line
        var inner1: Line
        
        var length: CGFloat {
            get {
                return self.outer0.length
            }
            set(v) {
                self.outer0.length = v
                self.inner1.length = v
            }
        }
        init(length: CGFloat, margin: CGFloat = 10.0) {
            self.outer0 = Line(length: length, margin: margin)
            self.inner1 = Line(length: length, margin: margin)
        }

        // When zooming in, this stores the geometric parameters
        var zoomGeometry: (
            // the origin on the line around which the outer labels are pushed outward, and from which the inner labels emerge
            origin: CGFloat,
            // the scale by which distances are expanded at the maximum extent of zooming in
            scale: CGFloat,
            // the offset added to items at the maximum extent of zooming in; it is scaled proportionally with zoom extent
            offset: CGFloat
        )?
        
        mutating func setOuterItemSizes(_ sizes: [CGFloat]) {
            self.outer0.itemSizes = sizes
        }
        
        func innerDelta(forSizes sizes: [CGFloat], zoomOrigin: CGFloat) -> CGFloat {
            let centre = self.length * 0.5
            let rawΔ = zoomOrigin - centre
            let halfSize = (sizes.isEmpty ? 0.0 : sizes.reduce(0,+) + (CGFloat(sizes.count-1)*self.inner1.itemGap)) * 0.5
            if rawΔ < 0.0 {
                let top = centre - halfSize
                return max(0.0, top+rawΔ) - top
            } else {
                let bottom = centre + halfSize
                return min(length-1, bottom+rawΔ) - bottom
            }
        }
        
        mutating func setInnerItemSizes(_ sizes: [CGFloat], openBelow index: Int) {
            let origin = self.zoomOrigin(forItemIndex: index)
            self.inner1.setSizes(sizes)
            self.inner1.calculateDelta(forZoomOrigin: origin)
            let δm = outer0.midpointGap(after: index)
            self.zoomGeometry = (
                origin: origin,
                scale: (self.inner1.extent + δm) / δm,
                offset: self.inner1.midpoint! - origin
            )
        }
        
        func calculateOuterPositions(forZoomExtent zoomExtent: CGFloat) -> [CGFloat] {
            guard let (origin, scale, maxOffset) = self.zoomGeometry else { return self.outer0.midpoints ?? [] }
            let ratio = 1.0 + (scale-1.0)*zoomExtent
            let offset = maxOffset * zoomExtent
            return self.outer0.midpointsScaled(by: ratio, from: origin).map { $0+offset }
        }
        
        func calculateInnerPositions(forZoomExtent zoomExtent: CGFloat) -> [CGFloat] {
            guard let (origin, _, _) = self.zoomGeometry else { return [] }
            return (self.inner1.midpoints ?? []).map { origin * (1-zoomExtent) + $0 * zoomExtent }
        }
        
        func zoomOrigin(forItemIndex index: Int) -> CGFloat {
            return self.outer0.trailingBoundary(after: index)
        }
    }
    
    // MARK: UI/geometry settings
    var font: UIFont { return UIFont.boldSystemFont(ofSize: 12.0) }
    
    let highlightedBarBackgroundColor = UIColor(white: 0.92, alpha: 0.5)
    let normalBarBackgroundColor = UIColor(white: 1.0, alpha: 0.5)
    let dimmedTintColour = UIColor.lightGray
    
    let zoomDistance: CGFloat = 25.0
    let innerLabelViewPadding: CGFloat = 4.0
    let innerLabelViewMargin: CGFloat = 4.0
    
    let closeAnimationSpeed: CGFloat = 3.5 // in zoomExtent units/second
    
    // MARK: lifecycle and UIKit interfacing
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        self.setupGeometry()
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
    
    override func awakeFromNib() {
        super.awakeFromNib()
        self.setupGeometry()
    }
    
    override var intrinsicContentSize: CGSize {
        if self.isHorizontal {
            return CGSize(
                width: max(self.frame.size.width, self.lineModel.outer0.extent),
                height: max(self.frame.size.height, self.topDisplayableMarkers?.first?.image.size.height ?? 0))
        } else {
            return CGSize(
                width: max(self.frame.size.width, (self.topDisplayableMarkers?.first?.image.size.width ?? 0) * 2),
                height: max(self.frame.size.height, self.lineModel.outer0.extent))
        }
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        let length = self.selectionDimension(self.frame.size)  - 2*innerLabelViewPadding
        if length != self.lineModel.length {
            self.lineModel.length = length
            self.interactionState = .ready
            self.recalcTopMarkerContextAndSizes()
            self.setNeedsDisplay()
        }
    }
    
    override func tintColorDidChange() {
        super.tintColorDidChange()
        self.recalcTopMarkerContextAndSizes()
        self.setNeedsDisplay()
    }
    
    // MARK: -------- UI elements
    
    let innerLabelFrameView = UIView()
    
    private func setupGeometry() {
        self.isOpaque = false
        self.lineModel.length = self.selectionDimension(self.frame.size) - 2*innerLabelViewPadding
        self.addSubview(self.innerLabelFrameView)
        self.innerLabelFrameView.frame = .zero
    }

    // MARK: -------- The internal representation of a Marker, for purposes of displaying and tracking touches
    
    struct DisplayableMarker: KFIndexBarMarkerProtocol {
        let label: String
        let offset: Int        
        // the image, at a standard size
        let image: UIImage
        // The size, along the dimension of selection
        let size: CGFloat
    }
    
    // done in bulk as we need to compute the maximum size for the image
    fileprivate func makeDisplayable(_ markers: [KFIndexBarMarkerProtocol]) -> [DisplayableMarker] {
        let everywhere = CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        let attribs: [NSAttributedStringKey:Any] = [
            .font: self.font,
            .foregroundColor: self.tintColor
        ]
        let markerSizes = markers.map { $0.label.boundingRect(with: everywhere, options: .usesLineFragmentOrigin, attributes: attribs, context: nil).size }
        let maxMarkerSize = CGSize(
            width: ceil(markerSizes.map {$0.width}.max() ?? 0.0),
            height: ceil(markerSizes.map {$0.height}.max() ?? 0.0))
        
        return zip(markers, markerSizes).map { arg -> DisplayableMarker in
            let (marker, msize) = arg
            UIGraphicsBeginImageContextWithOptions(CGSize(width: maxMarkerSize.width, height: maxMarkerSize.height), false, 0.0)
            defer { UIGraphicsEndImageContext() }
            marker.label.draw(
                with:CGRect(origin: CGPoint(x:(maxMarkerSize.width-msize.width)*0.5, y:(maxMarkerSize.height-msize.height)*0.5), size: msize),
                options: .usesLineFragmentOrigin,
                attributes:attribs, context: nil)
            return DisplayableMarker(
                label: marker.label,
                offset: marker.offset,
                image: UIGraphicsGetImageFromCurrentImageContext()!,
                size: self.isHorizontal ? msize.width : msize.height )
        }
    }

    // MARK: -------- Current interaction state and working store
    
    var topDisplayableMarkers: [DisplayableMarker]?
    fileprivate func setTopMarkers(_ markers: [KFIndexBarMarkerProtocol]) {
        let displayable = self.makeDisplayable(markers)
        self.topDisplayableMarkers = displayable
        self.lineModel.setOuterItemSizes(displayable.map { $0.size })
    }
    
    private func recalcTopMarkerContextAndSizes() {
        if let markers = self.topDisplayableMarkers {
            self.setTopMarkers(markers)
        }
    }
    
    // MARK: ----- the Interaction State machine
    
    // this is to replace a bunch of state variables
    enum InteractionState {
        // Not currently being touched or animating;
        case ready
        case draggingTop
        // A transient state when the user has dragged to initiate a zoom;
        // this will go to either .zooming (if a zoom is possible) or back to .draggingTop (if not), with the
        // stte filled in
        case userDraggedToZoom(underTopIndex: Int)
        // the view is being dragged between top-level and a fully opened zoom level
        case zooming(topIndex: Int, innerMarkers: [DisplayableMarker], extent: CGFloat)
        // the view is fully opened, and the user is selecting from the inner-level items
        case draggingInner(topIndex: Int, innerMarkers: [DisplayableMarker])
        // This state sets up animations and transitions immediately to animatingShut
        case startAnimatingShut(from: CGFloat, topIndex: Int, innerMarkers: [DisplayableMarker])
        case animatingShut(topIndex: Int, innerMarkers: [DisplayableMarker], extent: CGFloat, lastFrameTime: CFTimeInterval)
    }
    
    var interactionState: InteractionState = .ready {
        didSet(previous) {
            // much of the control's behaviour is in here
            switch(self.interactionState) {
            case .ready:
                if case .animatingShut(_) = previous {
                    self.displayLink?.invalidate()
                    self.displayLink = nil
                }
                self.innerLabelFrameView.isHidden = true
                self.setNeedsDisplay()
                
            case .draggingTop:
                if case .zooming(_,_,_) = previous {
                    self.innerLabelFrameView.isHidden = true
                }
                self.setNeedsDisplay()
                
            case .userDraggedToZoom(let topIndex):
                guard
                    let innerMarkers = self.getInnerMarkers(underTopMarker: topIndex),
                    innerMarkers.count >= 2
                else {
                    self.interactionState = .draggingTop
                    break
                }
                let displayables = self.makeDisplayable(innerMarkers)
                self.lineModel.setInnerItemSizes(displayables.map { $0.size }, openBelow: topIndex)
                self.interactionState = .zooming(topIndex: topIndex, innerMarkers: displayables, extent: 0.0)
                self.innerLabelFrameView.isHidden = false
                break
                
            case .zooming(_, _, _):
                self.setNeedsDisplay()
                self.placeAndFillInnerLabelView()
                
            case .startAnimatingShut(let from, let topIndex, let innerMarkers):
                if from == 0.0 {
                    self.interactionState = .ready
                    break
                }
                self.displayLink = CADisplayLink(target: self, selector: #selector(animationTick))
                self.interactionState = .animatingShut(topIndex: topIndex, innerMarkers: innerMarkers, extent: from, lastFrameTime: CACurrentMediaTime())
                self.displayLink?.add(to: RunLoop.main, forMode: RunLoopMode.defaultRunLoopMode)
                
            default:
                break
            }
        }
    }
    var zoomExtent: CGFloat {
        switch(self.interactionState) {
        case .ready, .draggingTop, .userDraggedToZoom(_): return 0.0
        case .zooming(_, _, let extent): return extent
        case .draggingInner(_, _): return 1.0
        case .startAnimatingShut(let from, _, _): return from
        case .animatingShut(_, _, let extent, _): return extent
        }
    }
    
    var innerMarkers: [DisplayableMarker]? {
        switch(self.interactionState) {
        case .zooming(_, let innerMarkers, _): return innerMarkers
        case .draggingInner(_, let innerMarkers): return innerMarkers
        case .animatingShut(_, let innerMarkers, _, _): return innerMarkers
        default: return nil
        }
    }
    
    private func getInnerMarkers(underTopMarker markerIndex: Int) -> [Marker]? {
        guard
            let topMarkers = self.topDisplayableMarkers
            else { return nil }
        let offsetFrom = topMarkers[markerIndex].offset
        let offsetTo = markerIndex<topMarkers.count-1 ? topMarkers[markerIndex+1].offset : Int.max
        return self.dataSource?.indexBar(self, markersBetween: offsetFrom, and: offsetTo)
    }
    
    
    // MARK: The snap-shut animation mechanism. (As labels are drawn, we cannot use CoreAnimation for this.)
    // The parts of the state transition function taking place during animation are handled here
    var displayLink: CADisplayLink?
    
    @objc func animationTick(_ displayLink: CADisplayLink) {
        guard
            case .animatingShut(let topIndex, let innerMarkers, let extent, let lastFrameTime) = self.interactionState
        else { return }
        let now = displayLink.timestamp
        let timeElapsed = now - lastFrameTime
        let newExtent = max(0.0, extent - self.closeAnimationSpeed*CGFloat(timeElapsed))
        self.interactionState = (newExtent == 0.0) ? .ready : .animatingShut(topIndex: topIndex, innerMarkers: innerMarkers, extent: newExtent, lastFrameTime: now)
        self.setNeedsDisplay()
        self.placeAndFillInnerLabelView()
    }
    
    // MARK: --------
    
    var lineModel: LineModel = LineModel(length:0.0)
    
    // MARK: -------- orientation handling
    
    private var isHorizontal: Bool { return self.frame.size.width > self.frame.size.height }
    private func selectionCoord(_ point: CGPoint) -> CGFloat { return self.isHorizontal ? point.x : point.y }
    private func zoomingCoord(_ point: CGPoint) -> CGFloat { return self.isHorizontal ? point.y : point.x }
    private func selectionDimension(_ size: CGSize) -> CGFloat { return self.isHorizontal ? size.width : size.height }
    private func zoomingDimension(_ size: CGSize) -> CGFloat { return self.isHorizontal ? size.height : size.width }
    
    // MARK: -------
    
    func topLabelIndex(forPosition pos: CGFloat) -> Int? {
        return self.lineModel.outer0.findItem(forPosition:pos)
    }
    
    func innerLabelIndex(forPosition pos: CGFloat) -> Int? {
        return self.lineModel.inner1.findItem(forPosition:pos)
    }
    
    // MARK: -------- Drawing and image rendering
    override func draw(_ rect: CGRect) {
        if let topMarkers = self.topDisplayableMarkers {
            let topMids = self.lineModel.calculateOuterPositions(forZoomExtent: self.zoomExtent)
            
            let imgSize = topMarkers.first?.image.size ?? CGSize.zero
            let r = self.selectionDimension(imgSize)*0.5
            if
                let start = (topMids.first.map { $0 - r }),
                let end = (topMids.last.map { $0 + r }),
                let ctx = UIGraphicsGetCurrentContext()
            {
                let ext = end-start
                let x = self.isHorizontal ? start : 0.0
                let y = self.isHorizontal ? 0.0 : start
                let width = self.isHorizontal ? ext : self.frame.size.width
                let height = self.isHorizontal ? self.frame.size.height : ext
                ctx.addPath(UIBezierPath(roundedRect: CGRect(x: x, y: y, width: width, height: height), cornerRadius: innerLabelViewPadding).cgPath)
                ctx.setFillColor((self.isHighlighted ? self.highlightedBarBackgroundColor.withAlphaComponent(0.5*(1-self.zoomExtent)) : self.normalBarBackgroundColor).cgColor)
                ctx.closePath()
                ctx.fillPath()
            }
            
            if self.isHorizontal {
                let ypos = (self.frame.size.height - imgSize.height) * 0.5
                for (mid, mkr) in zip(topMids, topMarkers) {
                    mkr.image.draw(at: CGPoint(x: mid - mkr.image.size.width*0.5, y:ypos), blendMode: .normal, alpha: (1.0-0.5*self.zoomExtent))
                }
                
            } else {
                let xpos = (self.frame.size.width - imgSize.width) * 0.5
                for (mid, mkr) in zip(topMids, topMarkers) {
                    mkr.image.draw(at: CGPoint(x: xpos, y:mid - mkr.image.size.height*0.5), blendMode: .normal, alpha: (1.0-0.5*self.zoomExtent))
                }
            }
        }
    }
    
    private func placeAndFillInnerLabelView() {
        guard let markers = self.innerMarkers else { return }
        let innerMids = self.lineModel.calculateInnerPositions(forZoomExtent: self.zoomExtent)
        let curvedExtent = 1.0 - ((1.0-self.zoomExtent)*(1.0-self.zoomExtent))
        let rα = (self.lineModel.inner1.itemSizes?.first ?? 0)*0.5
        let rΩ = (self.lineModel.inner1.itemSizes?.last ?? 0)*0.5
        let markerImgSize = markers.first?.image.size ?? CGSize.zero
        let rowBreadth = self.zoomingDimension(markerImgSize)

        let x0:CGFloat, y0:CGFloat, w: CGFloat, h: CGFloat
        let margin = innerLabelViewMargin + innerLabelViewPadding
        if self.isHorizontal {
            let labelsLateralOffset = -((self.zoomDistance+55) * curvedExtent) - 0
            x0 = (innerMids.first ?? 0) - rα - margin
            y0 = labelsLateralOffset - ceil(rowBreadth*0.5) - margin
            w = (innerMids.last ?? 0) - x0 + rΩ + 2*margin
            h = rowBreadth + 2*margin
        } else {
            y0 = (innerMids.first ?? 0) - rα - margin
            w = rowBreadth + 2*margin
            x0 = min((self.frame.size.width - w) * 0.5, self.frame.size.width - w + margin)
            h = (innerMids.last ?? 0) - y0 + rΩ + margin
        }
        self.innerLabelFrameView.frame = CGRect(x: x0, y: y0, width: w, height: h)
        
        // -- Now, fill the view
        let imageSize = self.innerLabelFrameView.bounds.size
        UIGraphicsBeginImageContextWithOptions(imageSize, false, 0.0)
        defer { UIGraphicsEndImageContext() }
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        ctx.addPath(UIBezierPath(roundedRect: CGRect(x: innerLabelViewMargin, y: innerLabelViewMargin, width: imageSize.width - 2*innerLabelViewMargin, height: imageSize.height  - 2*innerLabelViewMargin), cornerRadius: innerLabelViewPadding).cgPath)
        ctx.setFillColor(self.highlightedBarBackgroundColor.withAlphaComponent(0.5*self.zoomExtent).cgColor)
        ctx.closePath()
        ctx.fillPath()

        if self.isHorizontal {
            let ypos = (imageSize.height - markerImgSize.height) * 0.5
            let xoff = innerLabelViewMargin-self.innerLabelFrameView.frame.origin.x
            
            for (mid, mkr) in zip(innerMids, markers) {
                mkr.image.draw(at: CGPoint(x:mid + xoff - mkr.image.size.width * 0.5, y:ypos), blendMode: .normal, alpha: self.zoomExtent)
            }
        } else {
            let xpos = (imageSize.width - markerImgSize.width) * 0.5
            let yoff = -self.innerLabelFrameView.frame.origin.y

            for (mid, mkr) in zip(innerMids, markers) {
                mkr.image.draw(at: CGPoint(x:xpos, y:mid + yoff - mkr.image.size.height * 0.5), blendMode: .normal, alpha: self.zoomExtent)
            }
        }
        
        let image = UIGraphicsGetImageFromCurrentImageContext()
        
        // CoreImage blurring is far too slow here; most of the work seems in communicating with the GPU, from CIContext.createCGImage(...)
        self.innerLabelFrameView.layer.contents = image?.cgImage
    }
    
    //MARK: --------

    func reloadData() {
        self.setTopMarkers(self.dataSource?.topLevelMarkers(forIndexBar: self) ?? [])
        self.setNeedsLayout()
        self.interactionState = .ready
    }
    
    //MARK: ----- event tracking
    
    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        let loc = touch.location(in: self)
        let sc = self.selectionCoord(loc)
        if let index = self.topLabelIndex(forPosition: sc), let offset = self.topDisplayableMarkers?[index].offset {
            self._currentOffset = offset
        }
        self.interactionState = .draggingTop
        return true
    }
    
    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        let loc = touch.location(in: self)
        let zc = self.zoomingCoord(loc), sc = self.selectionCoord(loc)
        let zoomExtent = min(1.0, max(0.0, -(zc / self.zoomDistance)))
        
        switch(self.interactionState) {
        case .draggingTop:
            if let topIndex = self.topLabelIndex(forPosition: sc) {
                if zc >= 0.0, let offset = self.topDisplayableMarkers?[topIndex].offset {
                    self._currentOffset = offset
                }
                if zc < 0.0 {
                    self.interactionState = .userDraggedToZoom(underTopIndex: topIndex)
                }
            }
        case .zooming(let topIndex, let innerMarkers, _):
            if zoomExtent == 1.0 {
                self.interactionState = .draggingInner(topIndex: topIndex, innerMarkers: innerMarkers)
            } else if zoomExtent == 0.0 {
                self.interactionState = .draggingTop
            } else {
                self.interactionState = .zooming(topIndex: topIndex, innerMarkers: innerMarkers, extent: zoomExtent)
            }
        case .draggingInner(_, let innerMarkers):
            if let index = innerLabelIndex(forPosition: sc) {
                self._currentOffset = innerMarkers[index].offset
            }
        default: break
        }
        return true
    }
    
    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        switch (self.interactionState) {
        case .zooming(let topIndex, let innerMarkers, let extent):
            self.interactionState = .startAnimatingShut(from: extent, topIndex: topIndex, innerMarkers: innerMarkers)
        case .draggingInner(let topIndex, let innerMarkers):
            self.interactionState = .startAnimatingShut(from: 1.0, topIndex: topIndex, innerMarkers: innerMarkers)
        default:
            self.interactionState = .ready
        }
    }
    
    override func cancelTracking(with event: UIEvent?) {
        self.interactionState = .ready
    }
}

// We make this a protocol for reasons of polymorphism
fileprivate protocol KFIndexBarMarkerProtocol {
    var label: String { get }
    var offset: Int { get }
}
