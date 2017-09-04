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
        let zoomClearance: CGFloat

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
        
        init(length: CGFloat, zoomClearance: CGFloat = 10.0) {
            self.length = length
            self.zoomClearance = zoomClearance
        }

        mutating func recalcOuterMidpoints() {
            guard let sizes = self.outerItemSizes, sizes.count >= 2 else {
                outerZoomRatio1 = (self.length+2*self.zoomClearance + (outerItemSizes?.first ?? 0.0)) / self.length
                self.outerItemMidpoints0 = self.outerItemSizes?.map{ $0 * 0.5 } ?? []
                return
            }
            let outerItemGap = (self.length - sizes.reduce(0,+)) / CGFloat(sizes.count - 1)
            outerZoomRatio1 = (self.length + self.zoomClearance*2) / outerItemGap
            self.outerItemMidpoints0 = sizes.reduce(([], 0)) {  (acc:([CGFloat],CGFloat), size:CGFloat) in
                
                (acc.0 + [acc.1+size*0.5], acc.1+size+outerItemGap)
                }.0
        }
        
        mutating func recalcInnerMidpoints() {
            guard let sizes = self.innerItemSizes, sizes.count >= 2 else {                     return
            }
            let innerItemGap = (self.length - sizes.reduce(0,+)) / CGFloat(sizes.count - 1)
            self.innerItemMidpoints1 = sizes.reduce(([], 0)) {  (acc:([CGFloat],CGFloat), size:CGFloat) in
                
                (acc.0 + [acc.1+size*0.5], acc.1+size+innerItemGap)
                }.0
        }
        
        func calculateOuterPositions(forZoomExtent zoomExtent: CGFloat, openBelow index: Int) -> [CGFloat] {
            guard let outerSizes = self.outerItemSizes, let outerMidpoints = self.outerItemMidpoints0, !outerSizes.isEmpty else { return [] }
            guard outerSizes.count > 1 else {
                let p0_1 = -(outerSizes[0]*0.5+self.zoomClearance)
                let d = p0_1 - outerMidpoints[0]
                return [outerMidpoints[0] + d*zoomExtent]
            }
            let m1: CGFloat, c1:CGFloat
            if index < outerSizes.count-1 {
                let r0 = outerSizes[index]*0.5, r1 = outerSizes[index+1]*0.5
                let p0 = outerMidpoints[index], p1 = outerMidpoints[index+1]
                m1 = (self.length + 2*self.zoomClearance + r0 + r1) / (p1 - p0)
                c1 = self.length + self.zoomClearance + r1 - m1*p1
            } else { // below the end
                let r0 = outerSizes[index-1]*0.5, r1 = outerSizes[index]*0.5
                let p0 = outerMidpoints[index-1], p1 = outerMidpoints[index]
                let gap = p1-p0-(r0+r1)
                m1 = (self.length + 2*self.zoomClearance) / gap
                c1 = self.length * m1 - self.zoomClearance
            }
            let m = 1.0 + (m1 - 1.0)*zoomExtent
            let c = c1 * zoomExtent
            return outerMidpoints.map { $0 * m + c }
        }
        
        func calculateInnerPositions(forZoomExtent zoomExtent: CGFloat, openBelow index: Int) -> [CGFloat] {
            let origin: CGFloat
            if let outerMidpoints = self.outerItemMidpoints0, let outerSizes = self.outerItemSizes {
                origin = (index < outerMidpoints.count-1) ? ((outerMidpoints[index]+outerSizes[index]*0.5)+(outerMidpoints[index+1]-outerSizes[index+1]*0.5))*0.5 : self.length-1.0
            } else {
                origin = self.length * 0.5
            }
            let innerZoomExtent = zoomExtent
            return (self.innerItemMidpoints1 ?? []).map { origin * (1-innerZoomExtent) + $0 * innerZoomExtent }
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
                    self.backView.addSubview(label)
                }
            }
            self.lineModel.innerItemSizes = (self.innerMarkerLabels ?? []).map { $0.intrinsicContentSize.height }
        }
    }
    
    var lineModel: LineModel = LineModel(length:0.0)
    
    let backView = UIView()
    
    private func setupGeometry() {
        self.lineModel.length = self.frame.size.height
        self.backView.backgroundColor = UIColor(white: 0.8, alpha: 0.5)
        self.backView.layer.cornerRadius = 8.0
        self.backView.frame = self.bounds
        self.backView.isUserInteractionEnabled = false
        self.addSubview(backView)
        
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
        let totalHeight0 = labels.map { $0.intrinsicContentSize.height }.reduce(0,+)
        let gap0 = labels.count>1 ? (self.frame.size.height - totalHeight0) / CGFloat(labels.count-1) : 1.0
        var offset: CGFloat = 0.0
        for (index, label) in labels.enumerated() {
            if pos < offset + label.intrinsicContentSize.height + gap0*0.5 { return index }
            offset += label.intrinsicContentSize.height + gap0
        }
        return nil
    }
    
    func topLabelIndex(forPosition pos: CGFloat) -> Int? {
        return self.topMarkerLabels.flatMap { self.label(from: $0, under: pos) }
    }
    
    func innerLabelIndex(forPosition pos: CGFloat) -> Int? {
        return self.innerMarkerLabels.flatMap { self.label(from: $0, under: pos) }
    }
    
    
    private func placeTopMarkerLabels() {
        if let labels = self.topMarkerLabels, !labels.isEmpty {
            
            let topMids = self.lineModel.calculateOuterPositions(forZoomExtent: self.zoomExtent, openBelow: self.lastLabelIndex ?? 0)
            
            for (label, mid) in zip(labels, topMids) {
                let hh = label.intrinsicContentSize.height * 0.5
                label.frame = CGRect(x: 0.0, y: floor(mid-hh), width: self.backView.frame.size.width, height: label.intrinsicContentSize.height)
            }
        }
        
    }
    
    private func placeInnerMarkerLabels() {
        if let labels = self.innerMarkerLabels, !labels.isEmpty {
            let innerMids = self.lineModel.calculateInnerPositions(forZoomExtent: self.zoomExtent, openBelow: self.lastLabelIndex ?? 0)
            for (label, mid) in zip(labels, innerMids) {
                let hh = label.intrinsicContentSize.height * 0.5
                label.frame = CGRect(x: 0.0, y: floor(mid-hh), width: self.frame.size.width, height: label.intrinsicContentSize.height)
                label.layer.opacity = Float(self.zoomExtent)
            }
        }
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        self.lineModel.length = self.frame.size.height
        let overhang = -self.zoomDistance * self.zoomExtent
        self.backView.frame = CGRect(x: overhang, y: 0.0, width: self.frame.size.width-overhang, height: self.frame.size.height)
        self.placeTopMarkerLabels()
        self.placeInnerMarkerLabels()
    }
    
    func reloadData() {
        self.topMarkers = self.dataSource?.topLevelMarkers(forIndexBar: self) ?? []
    }

    
    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        self._zoomExtent = 0.0
        self.snappedToZoomIn = false
        return true
    }
    
    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        let loc = touch.location(in: self)
        if loc.x >= 0.0 {
            self.lastLabelIndex = topLabelIndex(forPosition: loc.y)
            if let index = self.lastLabelIndex, let offset = self.topMarkers?[index].offset {
                self._currentOffset = offset
            }
        }
        if loc.x < 0.0 {
            if let index = self.lastLabelIndex, let topMarkers = self.topMarkers, let dataSource = self.dataSource, self.zoomInState == nil || self.zoomInState?.positionAbove != index {
                let offsetFrom = topMarkers[index].offset
                let offsetTo = index<topMarkers.count-1 ? topMarkers[index+1].offset - 1 : Int.max
                self.zoomInState = ZoomInState(positionAbove: index, markers: dataSource.indexBar(self, markersBetween: offsetFrom, and: offsetTo))
            }
        }
        if self.snappedToZoomIn, let zoomInState = self.zoomInState, let index = innerLabelIndex(forPosition: loc.y) {
            let marker = zoomInState.markers[index]
            self._currentOffset = marker.offset
        }
        
        self.zoomExtent = self.snappedToZoomIn ? 1.0 : min(1.0, max(0.0, -(loc.x / self.zoomDistance)))
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
}
