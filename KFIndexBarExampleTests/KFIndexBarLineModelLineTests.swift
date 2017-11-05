//
//  KFIndexBarLineModelLineTests.swift
//  KFIndexBarExampleTests
//
//  Created by acb on 05/11/2017.
//  Copyright © 2017 Kineticfactory. All rights reserved.
//
// Tests for KFIndexBar.LineModel.Line

import XCTest
@testable import KFIndexBarExample

class KFIndexBarLineModelLineTests: XCTestCase {
    
    func testCalculatesGeometryWithZeroDelta() {
        var line = KFIndexBar.LineModel.Line(length: 10.0, margin: 1.0)
        line.setSizes([3.0, 1.0, 2.0], andDelta: 0.0)
        XCTAssertEqual(line.midpoints!, [2.5, 5.5, 8.0])
        XCTAssertEqual(line.startPos!, 1.0)
        XCTAssertEqual(line.endPos!, 9.0)
        XCTAssertEqual(line.midpoint!, 5.0)
        XCTAssertEqual(line.extent, 8.0)
        XCTAssertEqual(line.itemGap, 1.0)
    }

    func testCalculatesGeometryWithNonzeroDelta() {
        var line = KFIndexBar.LineModel.Line(length: 10.0, margin: 1.0)
        line.setSizes([3.0, 1.0, 2.0], andDelta: -1.0)
        XCTAssertEqual(line.midpoints!, [1.5, 4.5, 7.0])
        XCTAssertEqual(line.startPos!, 0.0)
        XCTAssertEqual(line.endPos!, 8.0)
        XCTAssertEqual(line.midpoint!, 4.0)
        XCTAssertEqual(line.extent, 8.0)
        XCTAssertEqual(line.itemGap, 1.0)
    }

    func testMidpointsScaledBy() {
        var line = KFIndexBar.LineModel.Line(length: 10.0, margin: 1.0)
        line.setSizes([3.0, 1.0, 2.0], andDelta: 0.0)
        XCTAssertEqual(line.midpointsScaled(by: 2.0, from: 5.0), [0.0, 6.0, 11.0])
    }
}
