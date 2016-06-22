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

/**
 Constructs an internal NSObject, used to represent a UITableView into InfinityTableView.
 */

import UIKit

internal final class TableViewEngine: NSObject {
    
    var infinityTableView: InfinityTableView!
    var engine:InfinityEngine!
    var delegate: InfinityTableViewProtocol!
    var reloadControl:UIRefreshControl?
    
    // MARK: - Lifecycle
    
    init(infinityTableView:InfinityTableView, delegate:InfinityTableViewProtocol) {
        super.init()
        self.infinityTableView = infinityTableView
        self.delegate = delegate
        self.engine = InfinityEngine(infinityModifiers: infinityTableView.modifiers, withDelegate: self)
        self.setupTableView()
        
        self.initiateEngine()
    }
    
    func setupTableView() {
        
        // Set Table View Instance With Appropriate Object
        self.infinityTableView.tableView.delegate = self
        self.infinityTableView.tableView.dataSource = self
        self.infinityTableView.tableView.separatorStyle = .None
        
        // Get the Bundle
        var bundle:NSBundle!
        if let identifier = self.infinityTableView.cells.bundleIdentifier {
            bundle = NSBundle(identifier: identifier)
        } else {
            bundle = NSBundle.mainBundle()
        }
        
        // Register All Posible Nibs
        for nibName in self.infinityTableView.cells.cellNames {
            self.infinityTableView.tableView.registerNib(UINib(nibName: nibName, bundle: bundle), forCellReuseIdentifier: nibName)
        }
        
        // Register Loading Cell
        let loadingCellNibName:String = self.infinityTableView.cells.loadingCellName
        self.infinityTableView.tableView.registerNib(UINib(nibName: loadingCellNibName, bundle: bundle), forCellReuseIdentifier: loadingCellNibName)


        // Refresh Control
        if self.engine.modifiers.refreshControl == true {
            self.reloadControl = UIRefreshControl()
            self.reloadControl?.addTarget(self, action: #selector(TableViewEngine.reloadFromRefreshControl), forControlEvents: UIControlEvents.ValueChanged)
            self.infinityTableView.tableView.addSubview(self.reloadControl!)
        }
    }
    
    func initiateEngine() {
        self.engine.performDataFetch()
    }
    
    func reloadFromRefreshControl() {
        self.engine.resetData()
        self.initiateEngine()
    }
}

extension TableViewEngine: InfinityDataEngineDelegate {
    
    func getData(atPage page: Int, withModifiers modifiers: InfinityModifers, completion: (responsePayload: ResponsePayload) -> ()) {
        self.delegate.infinityData(atPage: page, withModifiers: modifiers, forSession: self.engine.sessionID) { (responsePayload) in
            
            if self.engine.responseIsValid(atPage: page, withReloadControl: self.reloadControl, withResponsePayload: responsePayload) == true {
                completion(responsePayload: responsePayload)
            }
        }
    }
    
    func dataDidRespond(withData data: [AnyObject]?) {
        self.delegate.infinintyDataResponse?(withData: data)
    }
    
    func buildIndexsForInsert(dataCount count: Int) -> [NSIndexPath] {
        var indexs = [NSIndexPath]()
        
        var numbObj:Int
        
        if self.engine.lastPageHit == true {
            
            if self.engine.dataCount == 0 {
                numbObj = count - 1
            } else {
                numbObj = count - 2
            }
            
        } else {
            if self.engine.dataCount == 0 {
                numbObj = count
            } else {
                numbObj = count - 1
            }
        }
        
        // Protect against negative indexes - it can happen, believe me.
        let beggingIndexCount:Int = self.engine.dataCount
        let endIndexCount:Int = self.engine.dataCount + numbObj
        
        // As long as we're not gonna cause an infinite loop, lets build those new indexes between corresponding values.
        if beggingIndexCount < endIndexCount {
            for index in (beggingIndexCount)...(endIndexCount) {
                let indexPath = NSIndexPath(forRow: index, inSection: 0)
                indexs.append(indexPath)
            }
        }
        
        return indexs
    }
    
    func dataEngine(responsePayload payload: ResponsePayload, withIndexPaths indexPaths: [NSIndexPath]?) {
        self.engine.dataCount = self.engine.dataFactory(payload)
    }
    
    func updateControllerView(atIndexes indexes: [NSIndexPath]?) {
        
        guard let indexes = indexes else {
            self.infinityTableView.tableView.reloadData()
            return
        }
        
        if self.infinityTableView.modifiers.forceReload == true {
            self.infinityTableView.tableView.reloadData()
            
        } else {
            
            let indexPathTuple = self.engine.splitIndexPaths(indexes)
            
            dispatch_async(dispatch_get_main_queue(), { () -> Void in
                
                if self.engine.dataCount <= kPlaceHolderCellCount {
                    self.infinityTableView.tableView.reloadData()
                } else {
                    self.infinityTableView.tableView.beginUpdates()
                    self.infinityTableView.tableView.reloadRowsAtIndexPaths(indexPathTuple.reloadIndexPaths, withRowAnimation: UITableViewRowAnimation.Fade)
                    self.infinityTableView.tableView.insertRowsAtIndexPaths(indexPathTuple.insertIndexPaths, withRowAnimation: UITableViewRowAnimation.Fade)
                    self.infinityTableView.tableView.endUpdates()
                }
                
            })
        }
    }
}

extension TableViewEngine: UITableViewDataSource {
    
    func numberOfSectionsInTableView(tableView: UITableView) -> Int {
        return 1
    }
    
    func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if self.engine.dataCount == 0 && self.engine.page == 1 {
            return kPlaceHolderCellCount
        } else {
            if self.engine.lastPageHit == true {
                return self.engine.dataCount
            } else {
                
                if self.engine.dataCount == 0 {
                    return self.engine.dataCount
                } else {
                    return self.engine.dataCount + 1
                }
            }
        }
    }
    
    func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        // Calculate if we are used force reload
        if self.infinityTableView.modifiers.infiniteScroll == true {
            self.engine.infinteScrollMonitor(indexPath)
        }
        
        // Check our indexdBy Type
        var indexNum:Int = 0
        if self.infinityTableView.modifiers.indexedBy == IndexType.Section {
            indexNum = indexPath.section
        } else {
            indexNum = indexPath.row
        }
        
        if self.engine.page == 1 {
            
            if indexNum == kPlaceHolderCellCount - 1 {
                
                if self.infinityTableView.modifiers.infiniteScroll == true {
                    
                    return self.delegate.infinityLoadingCell(indexPath)
                    
                } else {
                    return self.delegate.infinityCellForIndexPath(indexPath, withPlaceholder: true)
                }
                
            } else {
                return self.delegate.infinityCellForIndexPath(indexPath, withPlaceholder: true)
            }
            
        } else {
            
            if indexNum == self.engine.dataCount {
                
                if self.infinityTableView.modifiers.infiniteScroll == true {
                    
                    if self.engine.dataCount > 0 {
                        return self.delegate.infinityLoadingCell(indexPath)
                    } else {
                        return self.delegate.infinityCellForIndexPath(indexPath, withPlaceholder: true)
                    }
                    
                } else {
                    return self.delegate.infinityCellForIndexPath(indexPath, withPlaceholder: false)
                }
                
            } else {
                
                // Check if there was no data returned from the response
                if self.engine.dataCount == 0 {
                    return self.delegate.infinityCellForIndexPath(indexPath, withPlaceholder: true)
                } else {
                    return self.delegate.infinityCellForIndexPath(indexPath, withPlaceholder: false)
                }
            }
        }
    }
}

extension TableViewEngine:UITableViewDelegate {
    
    func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {
        self.delegate.infinityDidSelectItemAtIndexPath?(indexPath)
    }
    
    func tableView(tableView: UITableView, heightForRowAtIndexPath indexPath: NSIndexPath) -> CGFloat {
        
        // Check our indexdBy Type
        var indexNum:Int = 0
        if self.infinityTableView.modifiers.indexedBy == .Section {
            indexNum = indexPath.section
        } else {
            indexNum = indexPath.row
        }
        
        if self.engine.page == 1 {
            if indexNum == kPlaceHolderCellCount - 1 {
                if self.infinityTableView.modifiers.infiniteScroll == true {
                    return kCellHeight
                } else {
                    return self.delegate.infinityTableView(self.infinityTableView.tableView, heightForRowAtIndexPath: indexPath)
                }
            } else {
                return self.delegate.infinityTableView(self.infinityTableView.tableView, heightForRowAtIndexPath: indexPath)
            }
            
        } else {
            if self.engine.dataCount == indexNum {
                if self.infinityTableView.modifiers.infiniteScroll == true {
                    return kCellHeight
                } else {
                    return self.delegate.infinityTableView(self.infinityTableView.tableView, heightForRowAtIndexPath: indexPath)
                }
            } else {
                return self.delegate.infinityTableView(self.infinityTableView.tableView, heightForRowAtIndexPath: indexPath)
            }
        }
    }    
}