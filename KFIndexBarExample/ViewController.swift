//
//  ViewController.swift
//  KFIndexBarExample
//
//  Created by acb on 29/08/2017.
//  Copyright © 2017 Kineticfactory. All rights reserved.
//

import UIKit

class ViewController: UIViewController {
    
    @IBOutlet var collectionView: UICollectionView?
    var indexBar:  KFIndexBar?
    
    var items: [String] = surnames

    var indexConstraints: [NSLayoutAttribute:NSLayoutConstraint] = [:]

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        
        let indexBar = KFIndexBar(frame: .zero)
        self.view.addSubview(indexBar)
        indexBar.translatesAutoresizingMaskIntoConstraints = false
        for attr: NSLayoutAttribute in [ .left, .right, .bottom] {
            let c = NSLayoutConstraint(item: indexBar, attribute: attr, relatedBy: .equal, toItem: self.view, attribute: attr, multiplier: 1.0, constant: 0.0)
            self.view.addConstraint(c)
            self.indexConstraints[attr] = c
        }
        let topConstraint = NSLayoutConstraint(item: indexBar, attribute: .top, relatedBy: .equal, toItem: self.topLayoutGuide, attribute: .bottom, multiplier: 1.0, constant: 0.0)
        self.view.addConstraint(topConstraint)
        self.indexConstraints[.top] = topConstraint
        
        let cw = NSLayoutConstraint(item: indexBar, attribute: NSLayoutAttribute.width, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1.0, constant: 20.0)
        self.indexConstraints[.width] = cw
        self.view.addConstraint(cw)
        let ch = NSLayoutConstraint(item: indexBar, attribute: NSLayoutAttribute.height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1.0, constant: 40.0)
        self.view.addConstraint(ch)
        self.indexConstraints[NSLayoutAttribute.height] = ch

        if self.isIpad {
            self.indexConstraints[.width]?.isActive = false
            self.indexConstraints[.top]?.isActive = false
        } else {
            self.indexConstraints[.height]?.isActive = false
            self.indexConstraints[.left]?.isActive = false
        }
        
        indexBar.dataSource = self
        self.indexBar = indexBar
        
        indexBar.addTarget(self, action: #selector(self.indexViewValueChanged(sender:)), for: .valueChanged)
        
        (self.collectionView?.collectionViewLayout as? UICollectionViewFlowLayout)?.scrollDirection = self.isIpad ? .horizontal : .vertical

    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.indexBar?.reloadData()
    }
    
    func indexViewValueChanged(sender: KFIndexBar) {
        let offset = sender.currentOffset
        print(">>> \(offset)")
        collectionView?.scrollToItem(at: IndexPath(item:offset, section:0), at: self.isIpad ? .left : .top, animated: false)
    }
    
    var isIpad: Bool { return self.traitCollection.horizontalSizeClass == .regular }

}

extension ViewController: KFIndexBarDataSource {
    func topLevelMarkers(forIndexBar: KFIndexBar) -> [KFIndexBar.Marker] {
        let groups = items.group(byKey: { $0.isEmpty ? "" : "\($0[$0.startIndex])".uppercased() }, transform: {$0})
        let markers: [KFIndexBar.Marker] = groups.reduce(([],0)) { (acc, group) -> ([KFIndexBar.Marker], Int) in
            (acc.0 + [KFIndexBar.Marker(label:group.0, offset:acc.1)], acc.1+group.1.count)
        }.0
        return markers
//        return groups.map { KFIndexBar.Marker(label: $0.0, offset: 0) } // FIXME
//        return [
//            KFIndexBar.Marker(label: "X", offset: 0),
//            KFIndexBar.Marker(label: "Y", offset: 100),
//            KFIndexBar.Marker(label: "Z", offset: 200)
//        ]
    }
    
    func indexBar(_ indexBar: KFIndexBar, markersBetween start: Int, and end: Int) -> [KFIndexBar.Marker] {
        let groups = items[start..<min(items.count,end)].map{$0}.group(byKey: { $0.isEmpty ? "" : $0.substring(to:$0.index($0.startIndex, offsetBy:min(2, $0.characters.count))).uppercased() }, transform: {$0})
        let markers: [KFIndexBar.Marker] = groups.reduce(([],start)) { (acc, group) -> ([KFIndexBar.Marker], Int) in
            (acc.0 + [KFIndexBar.Marker(label:group.0, offset:acc.1)], acc.1+group.1.count)
            }.0
        return markers
    }
}

extension ViewController: UICollectionViewDataSource {
    func numberOfSections(in collectionView: UICollectionView) -> Int {
        return 1
    }
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return items.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: CollectionViewCell.reuseIdentifier, for: indexPath) as? CollectionViewCell else { fatalError("Cannot deque cell") }
        cell.label?.text = items[indexPath.row]
        return cell
    }
}

extension ViewController: UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        return CGSize(width: (self.isIpad ? 320.0 : collectionView.frame.size.width), height: 40.0)
    }
}
