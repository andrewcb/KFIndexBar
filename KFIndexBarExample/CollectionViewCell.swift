//
//  CollectionViewCell.swift
//  KFIndexBarExample
//
//  Created by acb on 29/08/2017.
//  Copyright © 2017 Kineticfactory. All rights reserved.
//

import UIKit

class CollectionViewCell: UICollectionViewCell {
    class var reuseIdentifier: String { return "Cell" }
    
    @IBOutlet var label: UILabel?
}
