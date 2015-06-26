//
//  T8DataBaseManager.h
//  T8DataKitDemo
//
//  Created by 琦张 on 15/6/2.
//  Copyright (c) 2015年 琦张. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <FMDatabase.h>
#import <FMDatabaseQueue.h>

@interface T8DataBaseManager : NSObject

@property (nonatomic, assign) NSInteger dbVersion;

+ (T8DataBaseManager *)shareInstance;

- (void)setDbVersion:(NSInteger)dbVersion;

- (void)dispatchOnDatabaseThread:(void (^)(FMDatabase *db))block synchronous:(bool)synchronous;

@end
