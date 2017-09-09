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
        let outer0 = lineModel.calculateOuterPositions(forZoomExtent: 0.0, openBelow: 0)
        XCTAssertEqual(outer0, [2.0, 5.5, 8.5])
    }

    func testOuterItemPositions0Centering() {
        var lineModel = KFIndexBar.LineModel(length: 12.0, margin: 1.0)
        lineModel.outerItemSizes = [4.0, 1.0, 3.0 ]
        let outer0 = lineModel.calculateOuterPositions(forZoomExtent: 0.0, openBelow: 0)
        XCTAssertEqual(outer0, [3.0, 6.5, 9.5])
    }
    
    func testOuterItemPositions1() {
        var lineModel = KFIndexBar.LineModel(length: 10.0, margin: 1.0)
        lineModel.outerItemSizes = [4.0, 1.0, 3.0 ]
        let outer1 = lineModel.calculateOuterPositions(forZoomExtent: 1.0, openBelow: 0)
        print(outer1)
//        let (outer1, _) = lineModel.calculatePositions(forZoomExtent: 1.0, fixedPoint: 4.5)
        XCTAssertTrue(fabs(outer1[0] - (-(lineModel.margin + 2.0))) < 0.001)
        XCTAssertTrue(fabs(outer1[1] - (lineModel.length+lineModel.margin + 0.5)) < 0.001)
        
//        XCTAssertEqual(outer1, [CGFloat(-3.0), CGFloat(11.5), CGFloat(23.9286)])
    }

    func testOuterItemPositionsHalfway() {
        var lineModel = KFIndexBar.LineModel(length: 10.0, margin: 1.0)
        lineModel.outerItemSizes = [4.0, 1.0, 3.0 ]
        let outer1 = lineModel.calculateOuterPositions(forZoomExtent: 0.5, openBelow: 0)
        print(outer1)
        XCTAssert(fabs(outer1[0] - (-0.5)) < 0.0001)
        XCTAssert(fabs(outer1[1] - 8.5) < 0.0001)
//        XCTAssertEqual(outer1, [CGFloat(4.5 - 15.5*(2.5)), CGFloat(4.5 + 15.5*(1.0)), CGFloat(4.5 + 15.5*(4.0))])
    }

    func testInnerItemPositions0() {
        var lineModel = KFIndexBar.LineModel(length: 10.0)
        lineModel.outerItemSizes = [4.0, 1.0, 3.0 ]
        lineModel.innerItemSizes = [2.0, 2.0, 1.0, 2.0]
        let inner = lineModel.calculateInnerPositions(forZoomExtent: 0.0, openBelow: 0)
        XCTAssertEqual(inner, [4.5, 4.5, 4.5, 4.5])
        
    }
    
    func testInnerItemPositions1() {
        var lineModel = KFIndexBar.LineModel(length: 10.0)
        lineModel.outerItemSizes = [4.0, 1.0, 3.0 ]
        lineModel.innerItemSizes = [2.0, 2.0, 1.0, 2.0]
        let inner = lineModel.calculateInnerPositions(forZoomExtent: 1.0, openBelow: 0)
        XCTAssertEqual(inner, [1.0, 4.0, 6.5, 9.0])
        
    }
}
