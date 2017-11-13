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
    struct Marker {
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
    
    /** 0.0 = zoomed out on top-level headings; 1.0 = zoomed in, showing intermediate headings */
    var _zoomExtent: CGFloat = 0.0
    var snappedToZoomIn: Bool = false
    var zoomExtent: CGFloat {
        get { return self.snappedToZoomIn ? 1.0 : self._zoomExtent }
        set(v) {
            self._zoomExtent = v
            if v >= 1.0 { self.snappedToZoomIn = true }
            self.setNeedsDisplay()
            self.innerLabelFrameView.isHidden = (v == 0.0)
            if v > 0.0 {
                self.placeAndFillInnerLabelView()
            }
        }
    }
    
    // MARK: top-level marker state
    struct TopMarkerContext {
        let maxMarkerSize: CGSize
        let markerImages: [UIImage]
    }
    var topMarkerContext: TopMarkerContext?
    var topMarkers: [Marker]? {
        didSet(oldValue) {
            self.recalcTopMarkerContextAndSizes()
            self.setNeedsLayout()
        }
    }
    
    private func recalcTopMarkerContextAndSizes() {
        if let topMarkers = self.topMarkers {
            let (markerSizes, maxMarkerSize, markerImages) = self.sizesAndImages(forMarkers: topMarkers)
            self.topMarkerContext = TopMarkerContext(maxMarkerSize: maxMarkerSize, markerImages: markerImages)
            self.lineModel.setOuterItemSizes(markerSizes)
        }
    }
    
    // MARK: state to do with zooming in
    struct InnerMarkerContext {
        let positionAbove: Int
        let markers: [Marker]
        let maxMarkerSize: CGSize
        let markerImages: [UIImage]
    }
    
    var innerMarkerContext: InnerMarkerContext?
    
    private func innerMarkers(underTopMarker markerIndex: Int) -> [Marker]? {
        guard
            let topMarkers = self.topMarkers
            else { return nil }
        let offsetFrom = topMarkers[markerIndex].offset
        let offsetTo = markerIndex<topMarkers.count-1 ? topMarkers[markerIndex+1].offset : Int.max
        return self.dataSource?.indexBar(self, markersBetween: offsetFrom, and: offsetTo)
    }
    
    func initialiseInnerMarkers(underTopIndex index: Int) {
        guard
            let innerMarkers = self.innerMarkers(underTopMarker: index),
            self.innerMarkerContext == nil || self.innerMarkerContext?.positionAbove != index
        else { return }
        let (markerSizes, maxMarkerSize, markerImages) = self.sizesAndImages(forMarkers: innerMarkers)
        self.innerMarkerContext = InnerMarkerContext(positionAbove: index, markers: innerMarkers, maxMarkerSize: maxMarkerSize, markerImages: markerImages)
        self.lineModel.setInnerItemSizes(markerSizes, openBelow: index)
    }
    
    private func sizesAndImages(forMarkers markers: [Marker]) -> ([CGFloat], CGSize, [UIImage]) {
        let everywhere = CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        let attribs: [NSAttributedStringKey:Any] = [
            .font: self.font,
            .foregroundColor: self.tintColor
        ]
        let markerSizes = markers.map { $0.label.boundingRect(with: everywhere, options: .usesLineFragmentOrigin, attributes: attribs, context: nil).size }
        let maxMarkerSize = CGSize(
            width: ceil(markerSizes.map {$0.width}.max() ?? 0.0),
            height: ceil(markerSizes.map {$0.height}.max() ?? 0.0))
        
        let markerImages = zip(markers, markerSizes).map { arg -> UIImage in
            let (marker, msize) = arg
            UIGraphicsBeginImageContextWithOptions(CGSize(width: maxMarkerSize.width, height: maxMarkerSize.height), false, 0.0)
            defer { UIGraphicsEndImageContext() }
            marker.label.draw(
                with:CGRect(origin: CGPoint(x:(maxMarkerSize.width-msize.width)*0.5, y:(maxMarkerSize.height-msize.height)*0.5), size: msize),
                options: .usesLineFragmentOrigin,
                attributes:attribs, context: nil)
            return UIGraphicsGetImageFromCurrentImageContext()!
        }
        let sizeFunction: ((CGSize)->CGFloat) = isHorizontal ? { $0.width } : { $0.height }
        return (
            markerSizes.map(sizeFunction),
            maxMarkerSize,
            markerImages)
    }
    
    // ---- draw animation state
    enum AnimationState {
        case snapZoomOut(amountPerSecond: CGFloat)
    }
    var animationState: AnimationState? = nil {
        didSet {
            if self.animationState != nil {
                if self.displayLink == nil {
                    self.displayLink = CADisplayLink(target: self, selector: #selector(animationTick))
                }
                self.lastFrameTime = CACurrentMediaTime()
                self.displayLink?.add(to: RunLoop.main, forMode: RunLoopMode.defaultRunLoopMode)
            } else {
                self.displayLink?.invalidate()
                self.displayLink = nil
            }
        }
    }
    var lastFrameTime: CFTimeInterval? = nil
    var displayLink: CADisplayLink?
    
    @objc func animationTick(_ displayLink: CADisplayLink) {
        guard
            let animState = self.animationState,
            let lastFrameTime = self.lastFrameTime
        else { return }
        let timeElapsed = displayLink.timestamp - lastFrameTime
        self.lastFrameTime = displayLink.timestamp
        switch(animState) {
        case .snapZoomOut(let amountPerSecond):
            self.snappedToZoomIn = false
            self.zoomExtent = max(0.0, self.zoomExtent - amountPerSecond*CGFloat(timeElapsed))
            if self.zoomExtent == 0.0 {
                self.animationState = nil
            }
        }
    }
    
    var lineModel: LineModel = LineModel(length:0.0)
    
    let innerLabelFrameView = UIView()
    
    // MARK: orientation handling
    
    private var isHorizontal: Bool { return self.frame.size.width > self.frame.size.height }
    private func selectionCoord(_ point: CGPoint) -> CGFloat { return self.isHorizontal ? point.x : point.y }
    private func zoomingCoord(_ point: CGPoint) -> CGFloat { return self.isHorizontal ? point.y : point.x }
    private func selectionDimension(_ size: CGSize) -> CGFloat { return self.isHorizontal ? size.width : size.height }
    private func zoomingDimension(_ size: CGSize) -> CGFloat { return self.isHorizontal ? size.height : size.width }
    
    // MARK: ----------------
    
    private func setupGeometry() {
        self.isOpaque = false
        self.lineModel.length = self.selectionDimension(self.frame.size) - 2*innerLabelViewPadding
        self.addSubview(self.innerLabelFrameView)
        self.innerLabelFrameView.frame = .zero
    }
    
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
        let breadth = (self.topMarkerContext?.maxMarkerSize.width ?? 0) * 2
        return CGSize(width: max(self.frame.size.width, breadth), height: max(self.frame.size.height, breadth))
    }
    
    var lastLabelIndex: Int? = nil
    
    func topLabelIndex(forPosition pos: CGFloat) -> Int? {
        return self.lineModel.outer0.findItem(forPosition:pos)
    }
    
    func innerLabelIndex(forPosition pos: CGFloat) -> Int? {
        return self.lineModel.inner1.findItem(forPosition:pos)
    }
    
    override func draw(_ rect: CGRect) {
        if let topMarkerContext = self.topMarkerContext {
            let topMids = self.lineModel.calculateOuterPositions(forZoomExtent: self.zoomExtent)
            
            let r = self.selectionDimension(topMarkerContext.maxMarkerSize)*0.5
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
                let ypos = (self.frame.size.height - topMarkerContext.maxMarkerSize.height) * 0.5
                for (mid, img) in zip(topMids, topMarkerContext.markerImages) {
                    img.draw(at: CGPoint(x: mid - topMarkerContext.maxMarkerSize.width*0.5, y:ypos), blendMode: .normal, alpha: (1.0-0.5*zoomExtent))
                }
                
            } else {
                let xpos = (self.frame.size.width - topMarkerContext.maxMarkerSize.width) * 0.5
                for (mid, img) in zip(topMids, topMarkerContext.markerImages) {
                    img.draw(at: CGPoint(x: xpos, y:mid - topMarkerContext.maxMarkerSize.height*0.5), blendMode: .normal, alpha: (1.0-0.5*zoomExtent))
                }
            }
        }
    }
    
    private func placeAndFillInnerLabelView() {
        guard let zoomInContext = self.innerMarkerContext else { fatalError("Can't place inner label view without context") }
        let innerMids = self.lineModel.calculateInnerPositions(forZoomExtent: self.zoomExtent)
        let curvedExtent = 1.0 - ((1.0-self.zoomExtent)*(1.0-self.zoomExtent))
        let rα = (self.lineModel.inner1.itemSizes?.first ?? 0)*0.5
        let rΩ = (self.lineModel.inner1.itemSizes?.last ?? 0)*0.5
        let rowBreadth = self.zoomingDimension(zoomInContext.maxMarkerSize)

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
            let ypos = (imageSize.height - zoomInContext.maxMarkerSize.height) * 0.5
            let xoff = innerLabelViewMargin-self.innerLabelFrameView.frame.origin.x
            
            for (mid, img) in zip(innerMids, zoomInContext.markerImages) {
                img.draw(at: CGPoint(x:mid + xoff - zoomInContext.maxMarkerSize.width * 0.5, y:ypos), blendMode: .normal, alpha: zoomExtent)
            }
        } else {
            let xpos = (imageSize.width - zoomInContext.maxMarkerSize.width) * 0.5
            let yoff = -self.innerLabelFrameView.frame.origin.y

            for (mid, img) in zip(innerMids, zoomInContext.markerImages) {
                img.draw(at: CGPoint(x:xpos, y:mid + yoff - zoomInContext.maxMarkerSize.height * 0.5), blendMode: .normal, alpha: zoomExtent)
            }
        }
        
        let image = UIGraphicsGetImageFromCurrentImageContext()
        
        // CoreImage blurring is far too slow here; most of the work seems in communicating with the GPU, from CIContext.createCGImage(...)
        self.innerLabelFrameView.layer.contents = image?.cgImage
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        let length = self.selectionDimension(self.frame.size)  - 2*innerLabelViewPadding
        if length != self.lineModel.length {
            self.lineModel.length = length
            self.zoomExtent = 0.0
            self.recalcTopMarkerContextAndSizes()
            self.setNeedsDisplay()
        }
    }
    
    func reloadData() {
        self.topMarkers = self.dataSource?.topLevelMarkers(forIndexBar: self) ?? []
        self._zoomExtent = 0.0
        self.setNeedsLayout()
        self.setNeedsDisplay()
    }
    
    override func tintColorDidChange() {
        super.tintColorDidChange()
        self.recalcTopMarkerContextAndSizes()
        self.setNeedsDisplay()
    }

    //MARK: event tracking
    
    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        self._zoomExtent = 0.0
        self.snappedToZoomIn = false
        let loc = touch.location(in: self)
        let sc = self.selectionCoord(loc)
        self.lastLabelIndex = topLabelIndex(forPosition: sc)
        if let index = self.lastLabelIndex, let offset = self.topMarkers?[index].offset {
            self._currentOffset = offset
        }
        return true
    }
    
    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        let loc = touch.location(in: self)
        let zc = self.zoomingCoord(loc), sc = self.selectionCoord(loc)
        if !self.snappedToZoomIn {
            if zc >= 0.0 {
                self.lastLabelIndex = topLabelIndex(forPosition: sc)
                if let index = self.lastLabelIndex, let offset = self.topMarkers?[index].offset {
                    self._currentOffset = offset
                }
            }
            if zc < 0.0 {
                if let index = self.lastLabelIndex {
                    self.initialiseInnerMarkers(underTopIndex: index)
                }
            }
        }
        if self.snappedToZoomIn, let zoomInState = self.innerMarkerContext, let index = innerLabelIndex(forPosition: sc) {
            let marker = zoomInState.markers[index]
            self._currentOffset = marker.offset
        }
        
        let canZoomIn = !(self.innerMarkerContext?.markers.isEmpty ?? true)
        self.zoomExtent = canZoomIn ? (self.snappedToZoomIn ? 1.0 : min(1.0, max(0.0, -(zc / self.zoomDistance)))) : 0.0
        return true
    }
    
    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        self.animationState = .snapZoomOut(amountPerSecond: 3.5)
    }
    
    override func cancelTracking(with event: UIEvent?) {
        self.animationState = .snapZoomOut(amountPerSecond: 3.5)
    }
    
}

