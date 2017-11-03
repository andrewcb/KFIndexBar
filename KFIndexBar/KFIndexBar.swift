//
//  KFIndexBar.swift
//  KFIndexBarExample
//
//  Created by acb on 29/08/2017.
//  Copyright © 2017 Kineticfactory. All rights reserved.
//

import UIKit

protocol KFIndexBarDataSource {
    func topLevelMarkers(forIndexBar: KFIndexBar) -> [KFIndexBar.Marker]
    
    func indexBar(_ indexBar: KFIndexBar, markersBetween start: Int, and end: Int) -> [KFIndexBar.Marker]
}

class KFIndexBar: UIControl {
    struct Marker {
        let label: String
        let offset: Int
    }
    
    var dataSource: KFIndexBarDataSource? = nil
    
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
        // an individual line of items, with sizes and midpoints; the line model maintains two: an outer and an inner one
        struct Line {
            var length: CGFloat { didSet { self.recalculate() } }
            let margin: CGFloat

            var itemSizes: [CGFloat]? = nil { didSet { self.recalculate() } }
            var midpoints: [CGFloat]? = nil
            var itemGap: CGFloat = 0.0
            
            init(length: CGFloat, margin: CGFloat) {
                self.length = length
                self.margin = margin
            }
            
            mutating func recalculate() {
                guard let sizes = self.itemSizes, sizes.count >= 2 else {
                    self.midpoints = self.itemSizes.map { $0.map { _ in self.length * 0.5} }
                    self.itemGap = self.margin
                    return
                }
                let totalSize =  sizes.reduce(0,+)
                self.itemGap = min(margin, (self.length - totalSize) / CGFloat(sizes.count - 1))
                let startPos:CGFloat = (self.length - (totalSize + CGFloat(sizes.count-1) * itemGap)) * 0.5
                self.midpoints = (sizes.reduce(([], startPos)) {  (acc:([CGFloat],CGFloat), size:CGFloat) in
                    (acc.0 + [acc.1+size*0.5], acc.1+size+itemGap)
                }).0
            }
            
            var startPos: CGFloat? { return midpoints?.first.flatMap { (mp) in self.itemSizes?.first.flatMap { (sz) in mp - sz*0.5 } } }
            var endPos: CGFloat? { return midpoints?.last.flatMap { (mp) in self.itemSizes?.last.flatMap { (sz) in mp + sz*0.5 } } }

            func findItem(forPosition pos: CGFloat) -> Int? {
                guard
                    let midpoints = self.midpoints,
                    let sizes = self.itemSizes,
                    let startPos = self.startPos,
                    let endPos = self.endPos,
                    pos >= startPos,
                    pos <= endPos
                    else { return nil }
                return (zip(midpoints, sizes).enumerated().first { ($0.element.0 - ($0.element.1*0.5)) >= pos }?.offset).map { $0 - 1 } ?? (midpoints.count-1)
            }
        }
        
        var outer0: Line
        var inner1: Line
        
        var length: CGFloat {
            didSet {
                self.outer0.length = length
                self.inner1.length = length
            }
        }
        
        private mutating func recalcZoomRatio() {
            self.outerZoomRatio1 = (self.outer0.length + self.outer0.margin*2) / self.outer0.itemGap
        }
        // The distance between the nearest outer label, when moved out of the frame, and the frame
        let margin: CGFloat
        
        var outerItemSizes: [CGFloat]? {
            get { return self.outer0.itemSizes }
            set(v) {
                self.outer0.itemSizes = v
                self.recalcZoomRatio()
            }
        }
        var innerItemSizes: [CGFloat]? {
            get { return self.inner1.itemSizes }
            set(v) { self.inner1.itemSizes = v }
        }
        
        var outerZoomRatio1: CGFloat = 1.0
        
        init(length: CGFloat, margin: CGFloat = 10.0) {
            self.length = length
            self.margin = margin
            self.outer0 = Line(length: length, margin: margin)
            self.inner1 = Line(length: length, margin: margin)
        }
        
        func calculateOuterPositions(forZoomExtent zoomExtent: CGFloat, openBelow index: Int) -> [CGFloat] {
            guard
                let outerSizes = self.outer0.itemSizes,
                let outerMidpoints = self.outer0.midpoints,
                !outerSizes.isEmpty
            else { return [] }
            guard outerSizes.count > 1 else {
                let p0_1 = -(outerSizes[0]*0.5+self.margin)
                let d = p0_1 - outerMidpoints[0]
                return [outerMidpoints[0] + d*zoomExtent]
            }
            let m1: CGFloat, c1:CGFloat
            if index < outerSizes.count-1 {
                let r0 = outerSizes[index]*0.5, r1 = outerSizes[index+1]*0.5
                let p0 = outerMidpoints[index], p1 = outerMidpoints[index+1]
                m1 = (self.length + 2*self.margin + r0 + r1) / (p1 - p0)
                c1 = self.length + self.margin + r1 - m1*p1
            } else { // below the end
                let r0 = outerSizes[index-1]*0.5, r1 = outerSizes[index]*0.5
                let p0 = outerMidpoints[index-1], p1 = outerMidpoints[index]
                let gap = p1-p0-(r0+r1)
                m1 = (self.length + 2*self.margin) / gap
                c1 = self.length * m1 - self.margin
            }
            let m = 1.0 + (m1 - 1.0)*zoomExtent
            let c = c1 * zoomExtent
            return outerMidpoints.map { $0 * m + c }
        }
        
        /** returns: ([item midpoints], delta )
         where: delta is the offset from the centred inner midpoints
         */
        func calculateInnerPositions(forZoomExtent zoomExtent: CGFloat, openBelow index: Int) -> ([CGFloat], CGFloat) {
            let origin: CGFloat
            let centre = self.length * 0.5
            if let outerMidpoints = self.outer0.midpoints, let outerSizes = self.outerItemSizes {
                origin = (index < outerMidpoints.count-1) ? ((outerMidpoints[index]+outerSizes[index]*0.5)+(outerMidpoints[index+1]-outerSizes[index+1]*0.5))*0.5 : self.length-1.0
            } else {
                origin = centre
            }
            let oc = origin - centre
            let delta: CGFloat
            if
                let startPos = self.inner1.startPos,
                let endPos = self.inner1.endPos
            {
                if origin < centre {
                    delta =  max(0, startPos+oc) - startPos
                } else {
                    delta = min(self.length-1.0, endPos) - endPos
                }
            } else { delta = 0 }
            let innerZoomExtent = zoomExtent
            return ((self.inner1.midpoints ?? []).map { origin * (1-innerZoomExtent) + ($0+delta) * innerZoomExtent }, delta)
        }
    }
    
    //MARK: UI/geometry settings
    var font: UIFont { return UIFont.boldSystemFont(ofSize: 12.0) }
    
    let zoomDistance: CGFloat = 25.0
    
    /** 0.0 = zoomed out on top-level headings; 1.0 = zoomed in, showing intermediate headings */
    var _zoomExtent: CGFloat = 0.0
    var zoomExtent: CGFloat {
        get { return self.snappedToZoomIn ? 1.0 : self._zoomExtent }
        set(v) {
            self._zoomExtent = v
            if v >= 1.0 { self.snappedToZoomIn = true }
            self.setNeedsDisplay()
            if v == 0.0 {
                self.innerLabelFrameView.isHidden = true
            } else {
                self.innerLabelFrameView.isHidden = false
                self.placeAndFillInnerLabelView()
            }
        }
    }
    var snappedToZoomIn: Bool = false
    
    // touch state: tracking zoomed in points
    struct ZoomInContext {
        let positionAbove: Int
        let markers: [Marker]
        let markerSizes: [CGFloat]
        let maxMarkerSize: CGSize
        let markerImages: [UIImage]
        
        init(positionAbove: Int, markers: [Marker], font: UIFont, labelColour: UIColor, isHorizontal: Bool) {
            self.positionAbove = positionAbove
            self.markers = markers
            (self.markerSizes, self.maxMarkerSize, self.markerImages) = KFIndexBar.sizesAndImages(forMarkers: markers, withFont: font, labelColour: labelColour, isHorizontal: isHorizontal)
        }
    }
    
    var zoomInContext: ZoomInContext? {
        didSet { self.lineModel.innerItemSizes = self.zoomInContext?.markerSizes }
    }
    
    private class func sizesAndImages(forMarkers markers: [Marker], withFont font: UIFont, labelColour: UIColor, isHorizontal: Bool) -> ([CGFloat], CGSize, [UIImage]) {
        let everywhere = CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        let attribs: [NSAttributedStringKey:Any] = [
            .font: font,
            .foregroundColor: labelColour
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
        let sizeFunction = isHorizontal ? { (size: CGSize) in size.width } : { (size: CGSize) in size.height }
        return (
            markerSizes.map(sizeFunction),
            maxMarkerSize,
            markerImages)
    }
    
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
            let (markerSizes, maxMarkerSize, markerImages) = KFIndexBar.sizesAndImages(forMarkers: topMarkers, withFont: self.font, labelColour: self.tintColor, isHorizontal: self.isHorizontal)
            self.topMarkerContext = TopMarkerContext(maxMarkerSize: maxMarkerSize, markerImages: markerImages)
            self.lineModel.outerItemSizes = markerSizes
        }
    }
    
    // ---- draw animation state
    enum AnimationState {
        case snapZoomOut(amountPerSecond: CGFloat)
    }
    var animationState: AnimationState? = nil {
        didSet {
            if self.displayLink == nil {
                self.displayLink = CADisplayLink(target: self, selector: #selector(animationTick))
            }
            if self.animationState != nil {
                self.lastFrameTime = CACurrentMediaTime()
                self.displayLink.add(to: RunLoop.main, forMode: RunLoopMode.defaultRunLoopMode)
            } else {
                self.displayLink.invalidate()
                self.displayLink = nil
            }
        }
    }
    var lastFrameTime: CFTimeInterval? = nil
    var displayLink: CADisplayLink!// = CADisplayLink(target: self, selector: #selector(animationTick(:)))
    
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
        self.lineModel.length = self.frame.size.height
        self.addSubview(self.innerLabelFrameView)
        self.innerLabelFrameView.frame = .zero
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        self.setupGeometry()
        NotificationCenter.default.addObserver(self, selector: #selector(KFIndexBar.applicationWillResignActive(notification:)), name: .UIApplicationWillResignActive, object: nil)
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
    
    override func awakeFromNib() {
        super.awakeFromNib()
        self.setupGeometry()
        NotificationCenter.default.addObserver(self, selector: #selector(KFIndexBar.applicationWillResignActive(notification:)), name: .UIApplicationWillResignActive, object: nil)
    }
    
    override var intrinsicContentSize: CGSize {
        // FIXME
        print("intrinsicContentSize: self.bounds.size = \(self.bounds.size)")
        let breadth = (self.topMarkerContext?.maxMarkerSize.width ?? 0) * 2
        return CGSize(width: max(self.frame.size.width, breadth), height: max(self.frame.size.height, breadth))
    }
    
    func applicationWillResignActive(notification: NSNotification) {
        self.zoomExtent = 0.0
    }
    var lastLabelIndex: Int? = nil
    
    func topLabelIndex(forPosition pos: CGFloat) -> Int? {
        return self.lineModel.outer0.findItem(forPosition:pos)
    }
    
    func innerLabelIndex(forPosition pos: CGFloat) -> Int? {
        return self.lineModel.inner1.findItem(forPosition:pos-self.innerMarkerDelta)
    }
    
    override func draw(_ rect: CGRect) {
        if let topMarkerContext = self.topMarkerContext {
            let topMids = self.lineModel.calculateOuterPositions(forZoomExtent: self.zoomExtent, openBelow: self.lastLabelIndex ?? 0)
            
            let r = self.selectionDimension(topMarkerContext.maxMarkerSize)*0.5
            if
                let start = (topMids.first.map { $0 - r - innerLabelViewPadding }),
                let end = (topMids.last.map { $0 + r + 2*innerLabelViewPadding }),
                let ctx = UIGraphicsGetCurrentContext()
            {
                let ext = end-start
                let x = self.isHorizontal ? start : 0.0
                let y = self.isHorizontal ? 0.0 : start
                let width = self.isHorizontal ? ext : self.frame.size.width
                let height = self.isHorizontal ? self.frame.size.height : ext
                ctx.addPath(UIBezierPath(roundedRect: CGRect(x: x, y: y, width: width, height: height), cornerRadius: innerLabelViewPadding).cgPath)
                ctx.setFillColor(UIColor(white: 0.95, alpha: 0.5*(1-self.zoomExtent)).cgColor)
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
    
    
    let innerLabelViewPadding: CGFloat = 4.0
    let innerLabelViewMargin: CGFloat = 4.0
    
    /* The offset from the centre of the opened inner markers */
    var innerMarkerDelta: CGFloat = 0.0
    private func placeAndFillInnerLabelView() {
        guard let zoomInContext = self.zoomInContext else { fatalError("Can't place inner label view without context") }
        let (innerMids, innerDelta) = self.lineModel.calculateInnerPositions(forZoomExtent: self.zoomExtent, openBelow: self.lastLabelIndex ?? 0)
        self.innerMarkerDelta = innerDelta
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
        ctx.setFillColor(UIColor(white: 0.95, alpha: 0.5*self.zoomExtent).cgColor)
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
        let length = self.selectionDimension(self.frame.size)
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
    }
    
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
                if let index = self.lastLabelIndex, let topMarkers = self.topMarkers, let dataSource = self.dataSource, self.zoomInContext == nil || self.zoomInContext?.positionAbove != index {
                    let offsetFrom = topMarkers[index].offset
                    let offsetTo = index<topMarkers.count-1 ? topMarkers[index+1].offset : Int.max
                    self.zoomInContext = ZoomInContext(positionAbove: index, markers: dataSource.indexBar(self, markersBetween: offsetFrom, and: offsetTo), font: self.font, labelColour: self.tintColor, isHorizontal: self.isHorizontal)
                }
            }
        }
        if self.snappedToZoomIn, let zoomInState = self.zoomInContext, let index = innerLabelIndex(forPosition: sc) {
            let marker = zoomInState.markers[index]
            self._currentOffset = marker.offset
        }
        
        let canZoomIn = !(self.zoomInContext?.markers.isEmpty ?? true)
        self.zoomExtent = canZoomIn ? (self.snappedToZoomIn ? 1.0 : min(1.0, max(0.0, -(zc / self.zoomDistance)))) : 0.0
        return true
    }
    
    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        self.animationState = .snapZoomOut(amountPerSecond: 3.5)
    }
    
    override func tintColorDidChange() {
        super.tintColorDidChange()
        let color = (self.tintAdjustmentMode == .dimmed ? UIColor.lightGray : self.tintColor)
        self.recalcTopMarkerContextAndSizes()
        self.setNeedsDisplay()
    }
}

