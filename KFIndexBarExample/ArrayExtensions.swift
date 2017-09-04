//
//  ArrayExtensions.swift
//  KFIndexBarExample
//
//  Created by acb on 30/08/2017.
//  Copyright © 2017 Kineticfactory. All rights reserved.
//

import Foundation

extension Array {
    
    func group<U:Equatable, V>(byKey key: (Element)->U, transform: (Element)->V) -> [(U, [V])] {
        var result:[(U, [V])] = []
        
        var curKey:U? = nil
        var curItems: [V] = []
        
        for item in self {
            let k = key(item)
            
            if let ck = curKey, k != ck {
                let v = (ck, curItems) // the compiler doesn't like it otherwise
                result.append(v)
                curKey = .some(k)
                curItems = []
            } else {
                curKey = .some(k)
            }
            curItems.append(transform(item))
        }
        
        if let ck = curKey {
            let v = (ck, curItems)
            result.append(v)
        }
        return result
    }
}
