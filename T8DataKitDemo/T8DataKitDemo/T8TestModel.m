//
//  T8TestModel.m
//  T8DataKitDemo
//
//  Created by 琦张 on 15/6/2.
//  Copyright (c) 2015年 琦张. All rights reserved.
//

#import "T8TestModel.h"

@implementation T8TestModel

+ (NSString *)primaryKey
{
    return @"name";
}

+ (NSArray *)ignoreProperties
{
    return @[@"age"];
}

@end
