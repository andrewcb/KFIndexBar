//
//  KFIndexBarLineModelTests.swift
//  KFIndexBarExample
//
//  Created by acb on 02/09/2017.
//  Copyright © 2017 Kineticfactory. All rights reserved.
//

import XCTest
@testable import KFIndexBarExample

class KFIndexBarLineModelTests: XCTestCase {
    
    func testOuterItemPositions0() {
        var lineModel = KFIndexBar.LineModel(length: 10.0, margin: 1.0)
        lineModel.outerItemSizes = [4.0, 1.0, 3.0 ]
        let outer0 = lineModel.calculateOuterPositions(forZoomExtent: 0.0)
        XCTAssertEqual(outer0, [2.0, 5.5, 8.5])
    }

    func testOuterItemPositions0Centering() {
        var lineModel = KFIndexBar.LineModel(length: 12.0, margin: 1.0)
        lineModel.outerItemSizes = [4.0, 1.0, 3.0 ]
        let outer0 = lineModel.calculateOuterPositions(forZoomExtent: 0.0)
        XCTAssertEqual(outer0, [3.0, 6.5, 9.5])
    }
    
    func testInnerItemPositions0() {
        var lineModel = KFIndexBar.LineModel(length: 10.0)
        lineModel.outerItemSizes = [4.0, 1.0, 3.0 ]
        lineModel.setInnerItemSizes([2.0, 2.0, 1.0, 2.0], withDelta: 0.0, openBelow: 0)
        let inner = lineModel.calculateInnerPositions(forZoomExtent: 0.0)
        XCTAssertEqual(inner, [4.5, 4.5, 4.5, 4.5])
        
    }
    
    func testInnerItemPositions1() {
        var lineModel = KFIndexBar.LineModel(length: 10.0)
        lineModel.outerItemSizes = [4.0, 1.0, 3.0 ]
        lineModel.setInnerItemSizes([2.0, 2.0, 1.0, 2.0], withDelta: 0, openBelow: 0)
        let inner = lineModel.calculateInnerPositions(forZoomExtent: 1.0)
        XCTAssertEqual(inner, [1.0, 4.0, 6.5, 9.0])
        
    }
}
