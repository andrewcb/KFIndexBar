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
        var length: CGFloat {
            didSet {
                self.recalcOuterMidpoints()
                self.recalcInnerMidpoints()
            }
        }
        // The distance between the nearest outer label, when moved out of the frame, and the frame
        let margin: CGFloat
        
        var outerItemSizes: [CGFloat]? {
            didSet { self.recalcOuterMidpoints() }
        }
        var outerItemMidpoints0: [CGFloat]?
        var innerItemSizes: [CGFloat]? {
            didSet {
                self.recalcInnerMidpoints()
            }
        }
        var innerItemMidpoints1: [CGFloat]?
        
        var outerZoomRatio1: CGFloat = 1.0
        
        init(length: CGFloat, margin: CGFloat = 10.0) {
            self.length = length
            self.margin = margin
        }
        
        private func midpointsAndGap(for sizes: [CGFloat]) -> ([CGFloat], CGFloat) {
            guard sizes.count >= 2 else { return (sizes.map { _ in self.length*0.5 }, self.margin) }
            
            let totalSize =  sizes.reduce(0,+)
            let itemGap = min(margin, (self.length - totalSize) / CGFloat(sizes.count - 1))
            let startPos:CGFloat = (self.length - (totalSize + CGFloat(sizes.count-1) * itemGap)) * 0.5
            let midpoints = (sizes.reduce(([], startPos)) {  (acc:([CGFloat],CGFloat), size:CGFloat) in
                
                (acc.0 + [acc.1+size*0.5], acc.1+size+itemGap)
            }).0
            return (midpoints, itemGap)
        }
        
        mutating func recalcOuterMidpoints() {
            let (midpoints, itemGap) = self.outerItemSizes.map { self.midpointsAndGap(for: $0) } ?? ([], self.margin)
            self.outerItemMidpoints0 = midpoints
            self.outerZoomRatio1 = (self.length + self.margin*2) / itemGap
        }
        
        mutating func recalcInnerMidpoints() {
            self.innerItemMidpoints1 = (self.innerItemSizes.map { self.midpointsAndGap(for: $0).0 })
        }
        
        func calculateOuterPositions(forZoomExtent zoomExtent: CGFloat, openBelow index: Int) -> [CGFloat] {
            guard let outerSizes = self.outerItemSizes, let outerMidpoints = self.outerItemMidpoints0, !outerSizes.isEmpty else { return [] }
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
        
        func calculateInnerPositions(forZoomExtent zoomExtent: CGFloat, openBelow index: Int) -> [CGFloat] {
            let origin: CGFloat
            let centre = self.length * 0.5
            if let outerMidpoints = self.outerItemMidpoints0, let outerSizes = self.outerItemSizes {
                origin = (index < outerMidpoints.count-1) ? ((outerMidpoints[index]+outerSizes[index]*0.5)+(outerMidpoints[index+1]-outerSizes[index+1]*0.5))*0.5 : self.length-1.0
            } else {
                origin = centre
            }
            let oc = origin - centre
            let delta: CGFloat
            if
                let ma = self.innerItemMidpoints1?.first,
                let sa = self.innerItemSizes?.first,
                let mz = self.innerItemMidpoints1?.last,
                let sz = self.innerItemSizes?.last
            {
                if origin < centre {
                    let ea = ma-sa*0.5
                    delta =  max(0, ea+oc) - ea
                } else {
                    let ez = mz+sz*0.5
                    delta = min(self.length-1.0, ez+oc) - ez
                }
            } else { delta = 0 }
            let innerZoomExtent = zoomExtent
            return (self.innerItemMidpoints1 ?? []).map { origin * (1-innerZoomExtent) + ($0+delta) * innerZoomExtent }
        }
    }
    
    var font: UIFont { return UIFont.boldSystemFont(ofSize: 12.0) }
    
    let zoomDistance: CGFloat = 20.0
    
    /** 0.0 = zoomed out on top-level headings; 1.0 = zoomed in, showing intermediate headings */
    var _zoomExtent: CGFloat = 0.0
    var zoomExtent: CGFloat {
        get { return self.snappedToZoomIn ? 1.0 : self._zoomExtent }
        set(v) { self._zoomExtent = v ; if v >= 1.0 { self.snappedToZoomIn = true } ; self.setNeedsLayout() }
    }
    var snappedToZoomIn: Bool = false
    
    // touch state: tracking zoomed in points
    struct ZoomInState {
        var positionAbove: Int
        var markers: [Marker]
    }
    
    var zoomInState: ZoomInState? {
        didSet {
            self.innerMarkerLabels = self.zoomInState.map { $0.markers.map { self.makeLabel(from: $0) } }
        }
    }
    
    var topMarkers: [Marker]? {
        didSet(oldValue) {
            self.topMarkerLabels = self.topMarkers.map { $0.map { self.makeLabel(from: $0) } }
        }
    }
    
    private func makeLabel(from marker: Marker) -> UILabel {
        let label = UILabel()
        label.font = font
        label.text = marker.label
        label.textAlignment = .center
        label.textColor = self.tintColor
        label.sizeToFit()
        return label
    }
    
    var topMarkerLabels: [UILabel]? {
        didSet(oldValue) {
            if let oldLabels = oldValue {
                for l in oldLabels { l.removeFromSuperview() }
            }
            if let labels = self.topMarkerLabels, !labels.isEmpty {
                for label in labels {
                    self.backView.addSubview(label)
                }
            }
            self.lineModel.outerItemSizes = (self.topMarkerLabels ?? []).map { $0.intrinsicContentSize.height }
        }
    }
    var innerMarkerLabels: [UILabel]? {
        didSet(oldValue) {
            if let oldLabels = oldValue {
                for l in oldLabels { l.removeFromSuperview() }
            }
            if let labels = self.innerMarkerLabels, !labels.isEmpty {
                for label in labels {
                    self.innerLabelFrameView.addSubview(label)
                }
            }
            self.lineModel.innerItemSizes = (self.innerMarkerLabels ?? []).map { $0.intrinsicContentSize.height }
        }
    }
    
    var lineModel: LineModel = LineModel(length:0.0)
    
    let backView = UIView()
    let innerLabelFrameView: UIView = {
        let v = UIView()
        v.layer.cornerRadius = 8.0
        v.backgroundColor = UIColor(white: 0.95, alpha: 0.6)
        v.layer.borderColor = UIColor(white: 0.94, alpha: 0.6).cgColor
        v.layer.borderWidth = 1.0
        //        if #available(iOS 10.0, *) {
        //            if let filter = CIFilter(name: "CIGaussianBlur") {
        //                filter.setDefaults()
        //                filter.name = "blur"
        //                v.layer.filters = [ filter ]
        //                v.layer.setValue(5,
        //                               forKeyPath: "filters.blur.inputRadius")
        //            }
        //        }
        return v
    }()
    
    // MARK: orientation handling
    
    private var isHorizontal: Bool { return self.frame.size.width > self.frame.size.height }
    private func selectionCoord(_ point: CGPoint) -> CGFloat { return self.isHorizontal ? point.x : point.y }
    private func zoomingCoord(_ point: CGPoint) -> CGFloat { return self.isHorizontal ? point.y : point.x }
    private func selectionDimension(_ size: CGSize) -> CGFloat { return self.isHorizontal ? size.width : size.height }
    private func zoomingDimension(_ size: CGSize) -> CGFloat { return self.isHorizontal ? size.height : size.width }
    
    // MARK: ----------------
    
    
    private func setupGeometry() {
        self.lineModel.length = self.frame.size.height
        self.backView.backgroundColor = UIColor(white: 1.0, alpha: 0.5)
        self.backView.layer.cornerRadius = 8.0
        self.backView.frame = self.bounds
        self.backView.isUserInteractionEnabled = false
        self.addSubview(backView)
        backView.addSubview(self.innerLabelFrameView)
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
    
    var lastLabelIndex: Int? = nil
    
    private func label(from labels: [UILabel], under pos: CGFloat) -> Int? {
        guard let first = labels.first?.frame, let last = labels.last?.frame else { return nil }
        if pos < self.selectionCoord(first.origin) { return nil }
        if let index = (labels.enumerated().first { self.selectionCoord($0.element.frame.origin) > pos } ) { return index.offset - 1 }
        return pos < self.selectionCoord(last.origin)+self.selectionDimension(last.size) ? labels.count - 1 : nil
    }
    
    func topLabelIndex(forPosition pos: CGFloat) -> Int? {
        return self.topMarkerLabels.flatMap { self.label(from: $0, under: pos) }
    }
    
    func innerLabelIndex(forPosition pos: CGFloat) -> Int? {
        return self.innerMarkerLabels.flatMap { self.label(from: $0, under: pos - self.selectionCoord(self.innerLabelFrameView.frame.origin)) }
    }
    
    private func placeTopMarkerLabels() {
        if let labels = self.topMarkerLabels, !labels.isEmpty {
            
            let topMids = self.lineModel.calculateOuterPositions(forZoomExtent: self.zoomExtent, openBelow: self.lastLabelIndex ?? 0)
            
            for (label, mid) in zip(labels, topMids) {
                let r = self.selectionDimension(label.intrinsicContentSize) * 0.5
                if self.isHorizontal {
                    label.frame = CGRect(x: floor(mid-r), y:0, width: label.intrinsicContentSize.width,  height: self.backView.frame.size.height)
                } else {
                    label.frame = CGRect(x: 0.0, y: floor(mid-r), width: self.backView.frame.size.width, height: label.intrinsicContentSize.height)
                }
                label.layer.opacity = Float(1.0-self.zoomExtent)
            }
        }
    }
    
    private func placeInnerMarkerLabels() {
        if let labels = self.innerMarkerLabels, !labels.isEmpty {
            let rFirst = ceil(self.selectionDimension(labels.first!.intrinsicContentSize) * 0.5)
            let rLast = ceil(self.selectionDimension(labels.last!.intrinsicContentSize) * 0.5)
            // width/height of the row
            let rowBreadth = labels.map { self.zoomingDimension($0.bounds.size) }.max() ?? 0.0
            
            let innerMids = self.lineModel.calculateInnerPositions(forZoomExtent: self.zoomExtent, openBelow: self.lastLabelIndex ?? 0)
            let labelsLateralOffset: CGFloat
            let curvedExtent = 1.0 - ((1.0-self.zoomExtent)*(1.0-self.zoomExtent))
            if self.isHorizontal {
                labelsLateralOffset = -((self.zoomDistance+55) * curvedExtent) - 0
            } else {
                labelsLateralOffset = -((self.zoomDistance+80) * curvedExtent) - 0
            }
            
            let margin: CGFloat = 4.0, x0:CGFloat, y0:CGFloat, w: CGFloat, h: CGFloat
            if self.isHorizontal {
                x0 = (innerMids.first ?? 0) - rFirst - margin
                y0 = labelsLateralOffset - ceil(rowBreadth*0.5) - margin
                w = (innerMids.last ?? 0) - x0 + rLast + margin
                h = rowBreadth + 2*margin
            } else {
                y0 = (innerMids.first ?? 0) - rFirst - margin
                x0 = labelsLateralOffset - ceil(rowBreadth*0.5) - margin
                h = (innerMids.last ?? 0) - y0 + rLast + margin
                w = rowBreadth + 2*margin
            }
            
            self.innerLabelFrameView.frame = CGRect(x: x0, y: y0, width: w, height: h)
            
            for (label, mid) in zip(labels, innerMids) {
                if self.isHorizontal {
                    label.center = CGPoint(x: mid-x0, y:labelsLateralOffset-y0)
                } else {
                    label.center = CGPoint(x: labelsLateralOffset-x0, y: mid-y0)
                }
            }
            self.innerLabelFrameView.layer.opacity = Float(self.zoomExtent)
        }
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        self.lineModel.length = self.selectionDimension(self.frame.size)
        let overhang = -self.zoomDistance * self.zoomExtent
        if self.isHorizontal {
            self.backView.frame = CGRect(x: 0.0, y: overhang, width: self.frame.size.width, height: self.frame.size.height-overhang)
        } else {
            self.backView.frame = CGRect(x: overhang, y: 0.0, width: self.frame.size.width-overhang, height: self.frame.size.height)
        }
        self.placeTopMarkerLabels()
        self.placeInnerMarkerLabels()
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
                if let index = self.lastLabelIndex, let topMarkers = self.topMarkers, let dataSource = self.dataSource, self.zoomInState == nil || self.zoomInState?.positionAbove != index {
                    let offsetFrom = topMarkers[index].offset
                    let offsetTo = index<topMarkers.count-1 ? topMarkers[index+1].offset : Int.max
                    self.zoomInState = ZoomInState(positionAbove: index, markers: dataSource.indexBar(self, markersBetween: offsetFrom, and: offsetTo))
                }
            }
        }
        if self.snappedToZoomIn, let zoomInState = self.zoomInState, let index = innerLabelIndex(forPosition: sc) {
            let marker = zoomInState.markers[index]
            self._currentOffset = marker.offset
        }
        
        let canZoomIn = !(self.zoomInState?.markers.isEmpty ?? true)
        self.zoomExtent = canZoomIn ? (self.snappedToZoomIn ? 1.0 : min(1.0, max(0.0, -(zc / self.zoomDistance)))) : 0.0
        return true
    }
    
    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        UIView.setAnimationCurve(UIViewAnimationCurve.easeInOut)
        UIView.animate(withDuration: 0.2) {
            self._zoomExtent = 0.0
            self.snappedToZoomIn = false
            self.layoutSubviews()
        }
    }
    
    override func tintColorDidChange() {
        super.tintColorDidChange()
        let color = (self.tintAdjustmentMode == .dimmed ? UIColor.lightGray : self.tintColor)
        for label in self.topMarkerLabels ?? [] {
            label.textColor = color
        }
        for label in self.innerMarkerLabels ?? [] {
            label.textColor = color
        }
    }
}

