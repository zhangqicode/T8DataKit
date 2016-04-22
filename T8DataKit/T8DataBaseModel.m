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
#include <pthread.h>


static pthread_mutex_t propertyInfoDictLock;


@implementation T8DataBaseModel

- (id)init
{
    self = [super init];
    if (self) {
        
        NSDictionary *propertyInfos = [[self class] getPropertyInfo];
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
        NSDictionary *propertyInfos = [[self class] getPropertyInfo];
        NSArray *proNames = propertyInfos.allKeys;
        [proNames enumerateObjectsUsingBlock:^(NSString *name, NSUInteger idx, BOOL *stop) {
            id value = [dict objectForKey:name];
            if ([value isKindOfClass:[NSString class]]) {
                value = [self jsUnescape:value];
            }
            if (value && ![value isKindOfClass:[NSNull class]]) {
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
    [[self class] saveBatchItems:@[self] synchronous:sync];
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
            NSDictionary *propertyInfo = [self getPropertyInfo];
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
    if (![self primaryKey] || [[self primaryKey] isEqual:[NSNull null]]) {
        return;
    }
    
    [[self class] checkTable];
    
    [[T8DataBaseManager shareInstance] dispatchOnDatabaseThread:^(FMDatabase *db) {
        [db beginTransaction];
        NSDictionary *propertyInfos = [self getPropertyInfo];
        NSMutableArray *proNames = [propertyInfos.allKeys mutableCopy];
        NSArray *saveIgnores = [[self class] saveIgnoreProperties];
        [proNames removeObjectsInArray:saveIgnores];
        
        for (id item in items) {
            id primaryValue = [item valueForKey:[self primaryKey]];
            if (!primaryValue || [primaryValue isEqual:[NSNull null]]) {
                continue;
            }
            
            NSString *sqlStr = [NSString stringWithFormat:@"SELECT * FROM %@ WHERE %@ = '%@'", [[self class] tableName], [self primaryKey], [item valueForKey:[self primaryKey]]];
            FMResultSet *result = [db executeQuery:sqlStr];
            if ([result next]) {
                NSMutableString *queryFormat = [NSMutableString stringWithFormat:@"UPDATE %@ SET ", [[self class] tableName]];
                NSMutableArray *params = [NSMutableArray array];
                NSMutableArray *keyValues = [NSMutableArray array];
                [proNames enumerateObjectsUsingBlock:^(NSString * _Nonnull key, NSUInteger idx, BOOL * _Nonnull stop) {
                    [keyValues addObject:[NSString stringWithFormat:@"%@ = ?", key]];
                    NSString *type = [propertyInfos objectForKey:key];
                    id value = [item valueForKey:key];
                    if (value) {
                        if ([type hasPrefix:DBObject]) {
                            id<NSCoding> obj = value;
                            [params addObject:[NSKeyedArchiver archivedDataWithRootObject:obj]];
                        }else{
                            [params addObject:value];
                        }
                    } else {
                        [params addObject:[self defaultValueForDBType:type]];
                    }
                }];
                [queryFormat appendString:[keyValues componentsJoinedByString:@", "]];
                [queryFormat appendFormat:@" WHERE %@ = '%@'", [self primaryKey], [item valueForKey:[self primaryKey]]];
                [db executeUpdate:queryFormat withArgumentsInArray:params];
            }else{
                NSString *names = [proNames componentsJoinedByString:@", "];
                NSMutableArray *proArr = [NSMutableArray array];
                for (int i = 0; i < proNames.count; i++) {
                    [proArr addObject:@"?"];
                }
                NSString *values = [proArr componentsJoinedByString:@", "];
                NSString *queryFormat = [NSString stringWithFormat:@"INSERT INTO %@ (%@) VALUES (%@)", [[self class] tableName], names, values];
                
                NSMutableArray *params = [NSMutableArray array];
                for (int i = 0; i < proNames.count; i++) {
                    NSString *key = [proNames objectAtIndex:i];
                    NSString *type = [propertyInfos objectForKey:key];
                    id value = [item valueForKey:key];
                    if (value) {
                        if ([type hasPrefix:DBObject]) {
                            id<NSCoding> obj = value;
                            [params addObject:[NSKeyedArchiver archivedDataWithRootObject:obj]];
                        }else{
                            [params addObject:value];
                        }
                    } else {
                        [params addObject:[self defaultValueForDBType:type]];
                    }
                }
                [db executeUpdate:queryFormat withArgumentsInArray:params];
            }
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
    
    NSDictionary *propertyInfos = [self getPropertyInfo];
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


#pragma mark -
#pragma mark - get object properties

+ (NSDictionary *)getPropertyInfo
{
    static NSMutableDictionary *propertyInfoDict;
    static dispatch_once_t onceTokenForPropertyInfoDict;
    dispatch_once(&onceTokenForPropertyInfoDict, ^{
        propertyInfoDict = [[NSMutableDictionary alloc] init];
    });
    
    NSString *className = [NSStringFromClass([self class]) lowercaseString];
    
    pthread_mutex_lock(&propertyInfoDictLock);
    NSDictionary *classDict = [propertyInfoDict objectForKey:className];
    pthread_mutex_unlock(&propertyInfoDictLock);
    
    if (!classDict) {
        pthread_mutex_lock(&propertyInfoDictLock);
        //  在执行获取某个类的属性列表操作前再检查一次是否已经有了className对应的classDict，尽量避免（这个方案无法绝对保证同一个class同时只有一个线程在操作）多个线程同时获取同一个class的属性列表（可能有多个线程在同时操作一个className）
        //  之所以不在获取出行列表的时候加锁是因为：获取属性列表的操作耗时较长，简单的加锁会操成长时间的等待，因此采取允许多个线程同时获取同一个class的属性列表，但是在将获取的属性列表set到propertyInfoDict时进行检查，防止重复插入。只在简单的逻辑判断的地方加锁，在需要长时间操作的地方不加锁。
        NSDictionary *propertyInfo_before = [propertyInfoDict objectForKey:className];
        if (propertyInfo_before) {
            pthread_mutex_unlock(&propertyInfoDictLock);
            return [propertyInfo_before copy];
        }
        pthread_mutex_unlock(&propertyInfoDictLock);
        
        
        NSDictionary *classDict = [[NSMutableDictionary alloc] init];
        
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
                [((NSMutableDictionary *)classDict) setObject:type forKey:key];
            }
            free(properties);
            currentClass = class_getSuperclass(currentClass);
        }
        
        
        pthread_mutex_lock(&propertyInfoDictLock);
        //  在获取到某个类的属性列表操作后再检查一次是否已经有了className对应的classDict，防止重复插入相同的className（可能有多个线程在同时操作一个className）
        NSDictionary *propertyInfo_after = [propertyInfoDict objectForKey:className];
        if (propertyInfo_after) {
            pthread_mutex_unlock(&propertyInfoDictLock);
            return [propertyInfo_after copy];
        }
        
        [propertyInfoDict setObject:[classDict copy] forKey:className];
        pthread_mutex_unlock(&propertyInfoDictLock);
        
        return classDict;
    }
    
    return [classDict copy];
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

+ (id)defaultValueForDBType:(NSString *)dbType
{
    if ([dbType hasPrefix:DBText]) {
        return @"";
    } else if ([dbType hasPrefix:DBInt]) {
        return @(0);
    } else if ([dbType hasPrefix:DBFloat]) {
        return @(0.0f);
    } else if ([dbType hasPrefix:DBData]) {
        return [NSData data];
    } else if ([dbType hasPrefix:DBObject]) {
        NSString *classStr = [dbType substringFromIndex:DBObject.length + 1];
        if (classStr && classStr.length > 0) {
            Class class = NSClassFromString(classStr);
            if (class) {
                id<NSCoding> value =  [[class alloc] init];
                return value;
            }
        }
    }
    
    return [NSNull null];
}


#pragma mark -
#pragma mark - NSCoding

- (id)initWithCoder:(NSCoder *)aDecoder
{
    self = [super init];
    if (self) {
        NSDictionary *propertyInfoDict = [[self class] getPropertyInfo];
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
    NSDictionary *propertyInfoDict = [[self class] getPropertyInfo];
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
