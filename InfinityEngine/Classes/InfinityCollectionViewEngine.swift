// InfinityEngine
//
// Copyright Ryan Willis (c) 2016
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

import UIKit

/** 
 Constructs an internal NSObject, used to represent a UICollectionView into InfinityCollectionView.
 */

public class CollectionViewEngine: NSObject {
    
    var infinitCollectionView: InfinityCollectionView!
    var engine:InfinityEngine!
    var delegate: InfinityCollectionSourceable!
    var reloadControl:UIRefreshControl?

    // MARK: - Lifecycle
    
    init(infinityCollectionView:InfinityCollectionView) {
        super.init()
        self.infinitCollectionView = infinityCollectionView
        self.delegate = infinityCollectionView.delegate
        self.engine = InfinityEngine(infinityModifiers: infinitCollectionView.modifiers, withDelegate: self)
        self.setupCollectionView()
        self.initiateEngine()
    }
    
    func setupCollectionView() {
        // Set Table View Instance With Appropriate Object
        self.infinitCollectionView.collectionView.delegate = self
        self.infinitCollectionView.collectionView.dataSource = self
        self.infinitCollectionView.collectionView.alwaysBounceVertical = true
        
        
        // Get the Bundle 
        var bundle:NSBundle!
        if let identifier = self.infinitCollectionView.cells.bundleIdentifier {
            bundle = NSBundle(identifier: identifier)
        } else {
            bundle = NSBundle.mainBundle()
        }
        
        // Register All Posible Nibs
        for nibName in self.infinitCollectionView.cells.cellNames {
            self.infinitCollectionView.collectionView.registerNib(UINib(nibName: nibName, bundle: bundle), forCellWithReuseIdentifier: nibName)
        }
        
        // Register Loading Cell
        let loadingCellID = self.infinitCollectionView.cells.loadingCellName
        
        self.infinitCollectionView.collectionView.registerNib(UINib(nibName: loadingCellID,
            bundle: bundle), forSupplementaryViewOfKind: UICollectionElementKindSectionFooter,
                             withReuseIdentifier: loadingCellID)
        
        
        // Refresh Control
        if self.engine.modifiers.refreshControl == true {
            self.reloadControl = UIRefreshControl()
            self.reloadControl?.addTarget(self, action: #selector(CollectionViewEngine.reloadFromRefreshControl), forControlEvents: UIControlEvents.ValueChanged)
            self.infinitCollectionView.collectionView.addSubview(self.reloadControl!)
        }
    }
    
    func initiateEngine() {
        self.engine.performDataFetch()
    }
    
    func reloadFromRefreshControl() {
        self.engine.resetData()
        self.engine.performDataFetch()
    }
    
    func reloadCollectionView(indexes:[NSIndexPath]?) {
        self.infinitCollectionView.collectionView.reloadData()
    }
}

extension CollectionViewEngine: InfinityDataEngineDelegate {
    func getData(atPage page: Int, withModifiers modifiers: InfinityModifers, completion: (responsePayload: ResponsePayload) -> ()) {
        self.delegate.collectionView(self.infinitCollectionView.collectionView, withDataForPage: page, forSession: self.engine.sessionID) { (responsePayload) in
            if self.engine.responseIsValid(atPage: page, withReloadControl: self.reloadControl, withResponsePayload: responsePayload) == true {
                completion(responsePayload: responsePayload)
            }
        }
    }
    
    func dataDidRespond(withData data: [AnyObject]?) {
        self.delegate.infinintyDataResponse?(withData: data)
    }
    
    func updateControllerView() {
        self.infinitCollectionView.collectionView.reloadData()
    }
    
    public func scrollViewDidScroll(scrollView: UIScrollView) {
        self.engine.infinteScrollMonitor(scrollView)
    }
}

extension CollectionViewEngine: UICollectionViewDataSource {
    public func numberOfSectionsInCollectionView(collectionView: UICollectionView) -> Int {
        if self.engine.dataCount.count == 0 {
            return 1
        }
        return self.engine.dataCount.count
    }
    
    public func collectionView(collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        if self.engine.dataCount == [] {
            return kPlaceHolderCellCount
        } else {
            if self.engine.lastPageHit == false {
                if section == self.engine.dataCount.count - 1 {
                    return self.engine.dataCount[section] + 1
                }
            }
        }
        
        return self.engine.dataCount[section]
    }
    
    public func collectionView(collectionView: UICollectionView, cellForItemAtIndexPath indexPath: NSIndexPath) -> UICollectionViewCell {
        self.scrollViewDidScroll(self.infinitCollectionView.collectionView)
        
        let cell = self.delegate.collectionView(self.infinitCollectionView.collectionView, withCellItemForIndexPath: indexPath)
        if self.engine.page == 1 {
            if let placeholderableCell = cell as? InfinityCellPlaceholdable {
                placeholderableCell.showPlaceholder()
            }
        } else {
            if let placeholderableCell = cell as? InfinityCellPlaceholdable {
                placeholderableCell.hidePlaceholder()
            }
        }
        return cell
    }
}

extension CollectionViewEngine: UICollectionViewDelegate {
    public func collectionView(collectionView: UICollectionView, didSelectItemAtIndexPath indexPath: NSIndexPath) {
        self.delegate.collectionView?(collectionView, didSelectItemAtIndexPath: indexPath)
    }
    
    public func collectionView(collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String,
        atIndexPath indexPath: NSIndexPath) -> UICollectionReusableView {
        
        switch kind {
        case UICollectionElementKindSectionFooter:
            return self.delegate.collectionView(self.infinitCollectionView.collectionView,
                withLoadingCellItemForIndexPath: indexPath, forLastPageHit: self.engine.lastPageHit)
        default:
            return UICollectionReusableView()
        }
    }    
}

extension CollectionViewEngine: UICollectionViewDelegateFlowLayout {
    public func collectionView(collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout,
        referenceSizeForFooterInSection section: Int) -> CGSize {
        
        if section != self.engine.dataCount.count - 1 && self.engine.dataCount != [] || self.engine.lastPageHit {
            return CGSize(width: 0.0, height: 0.0)
        }

        return self.delegate.collectionView?(self.infinitCollectionView.collectionView, layout: collectionViewLayout, sizeForLoadingItemAtIndexPath: section) ??
                CGSize(width: UIScreen.mainScreen().bounds.size.width, height: kCellHeight)
    }
}

