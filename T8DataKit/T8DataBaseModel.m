//
//  T8DataBaseModel.m
//  T8DataKitDemo
//
//  Created by 琦张 on 15/6/1.
//  Copyright (c) 2015年 琦张. All rights reserved.
//

#import "T8DataBaseModel.h"
#import "T8DataBaseManager.h"
#import <objc/runtime.h>


@implementation T8DataBaseModel

- (id)init
{
    self = [super init];
    if (self) {
        
        NSMutableDictionary *propertyInfos = [[self class] getPropertyInfo];
        [propertyInfos enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *type, BOOL *stop) {
            if ([type hasPrefix:DBObject]) {
                NSArray *items = [type componentsSeparatedByString:@" "];
                if (items.count == 2) {
                    NSString *className = items.lastObject;
                    [self setValue:[[NSClassFromString(className) alloc] init] forKey:key];
                }
            }else if ([type isEqualToString:DBText]){
                [self setValue:@"" forKey:key];
            }else if ([type isEqualToString:DBData]){
                [self setValue:[NSData data] forKey:key];
            }
        }];
        
    }
    return self;
}

- (id)initWithDict:(NSDictionary *)dict
{
    self = [self init];
    if (self) {
        NSMutableDictionary *propertyInfos = [[self class] getPropertyInfo];
        NSArray *proNames = propertyInfos.allKeys;
        [proNames enumerateObjectsUsingBlock:^(NSString *name, NSUInteger idx, BOOL *stop) {
            id value = [dict objectForKey:name];
            if ([value isKindOfClass:[NSString class]]) {
                value = [self jsUnescape:value];
            }
            if (value) {
                [self setValue:value forKey:name];
            }
        }];
    }
    return self;
}

- (void)save
{
    [self saveSynchronous:false];
}

- (void)saveSynchronous:(BOOL)sync
{
    [[self class] checkTable];
    
    NSMutableDictionary *propertyInfos = [[self class] getPropertyInfo];
    NSMutableArray *proNames = [propertyInfos.allKeys mutableCopy];
    NSArray *saveIgnores = [[self class] saveIgnoreProperties];
    [proNames removeObjectsInArray:saveIgnores];
    NSString *names = [proNames componentsJoinedByString:@", "];
    NSMutableArray *proArr = [NSMutableArray array];
    for (int i = 0; i < proNames.count; i++) {
        [proArr addObject:@"?"];
    }
    NSString *values = [proArr componentsJoinedByString:@", "];
    NSString *queryFormat = [NSString stringWithFormat:@"INSERT OR REPLACE INTO %@ (%@) VALUES (%@)", [[self class] tableName], names, values];
    
    NSMutableArray *params = [NSMutableArray array];
    for (int i = 0; i < proNames.count; i++) {
        NSString *key = [proNames objectAtIndex:i];
        NSString *type = [propertyInfos objectForKey:key];
        id value = [self valueForKey:key];
        if ([type hasPrefix:DBObject]) {
            id<NSCoding> obj = value;
            [params addObject:[NSKeyedArchiver archivedDataWithRootObject:obj]];
        }else{
            [params addObject:value];
        }
    }
    
    [[T8DataBaseManager shareInstance] dispatchOnDatabaseThread:^(FMDatabase *db) {
        [db executeUpdate:queryFormat withArgumentsInArray:params];
    } synchronous:sync];
}

- (void)deleteObject
{
    [self deleteObjectSynchronous:false];
}

- (void)deleteObjectSynchronous:(BOOL)sync
{
    NSString *primaryKey = [[self class] primaryKey];
    NSString *queryFormat = [NSString stringWithFormat:@"DELETE FROM %@ WHERE %@ = ?", [[self class] tableName], primaryKey];
    NSArray *valueArr = [NSArray arrayWithObject:[self valueForKey:primaryKey]];
    
    [[T8DataBaseManager shareInstance] dispatchOnDatabaseThread:^(FMDatabase *db) {
        [db executeUpdate:queryFormat withArgumentsInArray:valueArr];
    } synchronous:sync];
}

+ (NSMutableArray *)queryWithCondition:(NSString *)condition
{
    NSString *queryFormat = [NSString stringWithFormat:@"SELECT * FROM %@ %@", [[self class] tableName], condition];
    NSMutableArray *resultArr = [NSMutableArray array];
    
    [[T8DataBaseManager shareInstance] dispatchOnDatabaseThread:^(FMDatabase *db) {
        
        FMResultSet *result = [db executeQuery:queryFormat];
        while ([result next]) {
            T8DataBaseModel *model = [[[self class] alloc] init];
            NSDictionary *propertyInfo = [[self class] getPropertyInfo];
            [propertyInfo enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *type, BOOL *stop) {
                id value;
                if ([type isEqualToString:DBInt]) {
                    value = @([result longLongIntForColumn:key]);
                }else if ([type isEqualToString:DBFloat]){
                    value = @([result doubleForColumn:key]);
                }else if ([type isEqualToString:DBText]){
                    value = [result stringForColumn:key];
                    if (value == nil) {
                        value = @"";
                    }
                }else if ([type isEqualToString:DBData]){
                    value = [result dataForColumn:key];
                }else if ([type hasPrefix:DBObject]){
                    value = [result dataForColumn:key];
                    value = [NSKeyedUnarchiver unarchiveObjectWithData:value];
                }
                if (value) {
                    [model setValue:value forKey:key];
                }
            }];
            [resultArr addObject:model];
        }
        
    } synchronous:true];
    
    return resultArr;
}

+ (void)saveBatchItems:(NSArray *)items
{
    [self saveBatchItems:items synchronous:false];
}

+ (void)saveBatchItems:(NSArray *)items synchronous:(BOOL)sync
{
    [[self class] checkTable];
    
    [[T8DataBaseManager shareInstance] dispatchOnDatabaseThread:^(FMDatabase *db) {
        [db beginTransaction];
        for (id item in items) {
            NSMutableDictionary *propertyInfos = [[self class] getPropertyInfo];
            NSArray *proNames = propertyInfos.allKeys;
            NSString *names = [proNames componentsJoinedByString:@", "];
            NSMutableArray *proArr = [NSMutableArray array];
            for (int i = 0; i < proNames.count; i++) {
                [proArr addObject:@"?"];
            }
            NSString *values = [proArr componentsJoinedByString:@", "];
            NSString *queryFormat = [NSString stringWithFormat:@"INSERT OR REPLACE INTO %@ (%@) VALUES (%@)", [[self class] tableName], names, values];
            
            NSMutableArray *params = [NSMutableArray array];
            for (int i = 0; i < proNames.count; i++) {
                NSString *key = [proNames objectAtIndex:i];
                NSString *type = [propertyInfos objectForKey:key];
                id value = [item valueForKey:key];
                if ([type hasPrefix:DBObject]) {
                    id<NSCoding> obj = value;
                    [params addObject:[NSKeyedArchiver archivedDataWithRootObject:obj]];
                }else{
                    [params addObject:value];
                }
            }
            [db executeUpdate:queryFormat withArgumentsInArray:params];
        }
        [db commit];
    } synchronous:sync];
}

+ (void)clearTableSynchronous:(BOOL)sync
{
    NSString *queryFormat = [NSString stringWithFormat:@"DELETE FROM %@", [[self class] tableName]];
    
    [[T8DataBaseManager shareInstance] dispatchOnDatabaseThread:^(FMDatabase *db) {
        [db executeUpdate:queryFormat];
    } synchronous:sync];
}

+ (void)deleteWithCondition:(NSString *)condition synchronous:(BOOL)sync
{
    NSString *queryFormat = [NSString stringWithFormat:@"DELETE FROM %@ %@", [[self class] tableName], condition];
    [[T8DataBaseManager shareInstance] dispatchOnDatabaseThread:^(FMDatabase *db) {
        [db executeUpdate:queryFormat];
    } synchronous:sync];
}

+ (void)checkTable
{
    NSMutableString *sql = [NSMutableString stringWithCapacity:0];
    [sql appendString:@"create table if not exists "];
    [sql appendString:NSStringFromClass([self class])];
    [sql appendString:@"("];
    
    NSMutableArray *propertyArr = [NSMutableArray arrayWithCapacity:0];
    
    NSMutableDictionary *propertyInfos = [[self class] getPropertyInfo];
    __weak typeof(self) weakSelf = self;
    [propertyInfos.allKeys enumerateObjectsUsingBlock:^(NSString *key, NSUInteger idx, BOOL *stop) {
        NSString *type = [propertyInfos objectForKey:key];
        if ([type hasPrefix:DBObject]) {
            type = DBData;
        }
        NSString *proStr;
        if ([key isEqualToString:[[weakSelf class] primaryKey]]) {
            proStr = [NSString stringWithFormat:@"%@ %@ primary key", [[weakSelf class] primaryKey], type];
        } else {
            proStr = [NSString stringWithFormat:@"%@ %@", key, type];
        }
        [propertyArr addObject:proStr];
    }];
    
    NSString *propertyStr = [propertyArr componentsJoinedByString:@","];
    
    [sql appendString:propertyStr];
    
    [sql appendString:@");"];
    
    [[T8DataBaseManager shareInstance] dispatchOnDatabaseThread:^(FMDatabase *db) {
        
        [db executeUpdate:sql];
        
    } synchronous:true];
}

+ (NSString *)tableName
{
    return [NSStringFromClass([self class]) lowercaseString];
}

+ (NSString *)primaryKey
{
    return nil;
}

+ (NSArray *)ignoreProperties
{
    return nil;
}

+ (NSArray *)saveIgnoreProperties
{
    return nil;
}

+ (NSMutableDictionary *)getPropertyInfo
{
    static NSMutableDictionary *propertyInfoDict;
    if (propertyInfoDict==nil) {
        propertyInfoDict = [NSMutableDictionary dictionary];
    }
    NSString *className = [NSStringFromClass([self class]) lowercaseString];
    NSMutableDictionary *classDict = [propertyInfoDict objectForKey:className];
    if (classDict==nil) {
        classDict = [NSMutableDictionary dictionary];
        Class currentClass = [self class];
        while (currentClass != [T8DataBaseModel class]) {
            unsigned int count;
            objc_property_t *properties = class_copyPropertyList(currentClass, &count);
            NSArray *ignores = [[self class] ignoreProperties];
            for (int i = 0; i < count; i++) {
                objc_property_t property = properties[i];
                NSString * key = [[NSString alloc]initWithCString:property_getName(property)  encoding:NSUTF8StringEncoding];
                if ([ignores containsObject:key]) {
                    continue;
                }
                NSString *type = [self dbTypeConvertFromObjc_property_t:property];
                [classDict setObject:type forKey:key];
            }
            free(properties);
            currentClass = class_getSuperclass(currentClass);
        }
        [propertyInfoDict setObject:classDict forKey:className];
    }
    return classDict;
}

+ (NSString *)dbTypeConvertFromObjc_property_t:(objc_property_t)property
{
    char * type = property_copyAttributeValue(property, "T");
    
    NSString *typeStr = DBText;
    switch(type[0]) {
        case 'f' : //float
        case 'd' : //double
        {
            typeStr = DBFloat;
        }
            break;
            
        case 'c':   // char
        case 's':   // short
        case 'i':   // int
        case 'l':   // long
        case 'q':   // NSInteger
        {
            typeStr = DBInt;
        }
            break;
            
        case '*':   // char *
            break;
            
        case '@' : //ObjC object
            //Handle different clases in here
        {
            NSString *cls = [NSString stringWithUTF8String:type];
            cls = [cls stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            cls = [cls stringByReplacingOccurrencesOfString:@"@" withString:@""];
            cls = [cls stringByReplacingOccurrencesOfString:@"\"" withString:@""];
            
            if ([NSClassFromString(cls) isSubclassOfClass:[NSString class]]) {
                typeStr = DBText;
            }else if ([NSClassFromString(cls) isSubclassOfClass:[NSNumber class]]) {
                typeStr = DBText;
            }else if ([NSClassFromString(cls) isSubclassOfClass:[NSData class]]) {
                typeStr = DBData;
            }else if ([NSClassFromString(cls) conformsToProtocol:@protocol(NSCoding)]) {
                typeStr = [DBObject stringByAppendingFormat:@" %@", cls];
            }
        }
            break;
    }
    
    free(type);
    
    return typeStr;
}

#pragma mark - NSCoding
- (id)initWithCoder:(NSCoder *)aDecoder
{
    self = [super init];
    if (self) {
        NSMutableDictionary *propertyInfoDict = [[self class] getPropertyInfo];
        [propertyInfoDict enumerateKeysAndObjectsUsingBlock:^(NSString *propertyName, NSString *type, BOOL *stop) {
            id value = [aDecoder decodeObjectForKey:propertyName];
            if ([type hasPrefix:DBObject]) {
                value = [NSKeyedUnarchiver unarchiveObjectWithData:value];
            }
            [self setValue:value forKey:propertyName];
        }];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder
{
    NSMutableDictionary *propertyInfoDict = [[self class] getPropertyInfo];
    [propertyInfoDict enumerateKeysAndObjectsUsingBlock:^(NSString *propertyName, NSString *type, BOOL *stop) {
        id value = [self valueForKey:propertyName];
        if ([type hasPrefix:DBObject]) {
            value = [NSKeyedArchiver archivedDataWithRootObject:value];
        }
        [aCoder encodeObject:value forKey:propertyName];
    }];
}

- (NSString *)jsUnescape:(NSString *)str
{
    str = [str stringByReplacingOccurrencesOfString:@"&amp;" withString:@"&"];
    str = [str stringByReplacingOccurrencesOfString:@"&lt;" withString:@"<"];
    str = [str stringByReplacingOccurrencesOfString:@"&gt;" withString:@">"];
    str = [str stringByReplacingOccurrencesOfString:@"&quot;" withString:@"\""];
    str = [str stringByReplacingOccurrencesOfString:@"&apos;" withString:@"\\"];
    str = [str stringByReplacingOccurrencesOfString:@"&#x2F;" withString:@"/"];
    return str;
}

@end
