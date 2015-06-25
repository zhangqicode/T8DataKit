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

- (id)initWithDict:(NSDictionary *)dict
{
    self = [super init];
    if (self) {
        NSMutableDictionary *propertyInfos = [[self class] getPropertyInfo];
        NSArray *proNames = propertyInfos.allKeys;
        [proNames enumerateObjectsUsingBlock:^(NSString *name, NSUInteger idx, BOOL *stop) {
            id value = [dict objectForKey:name];
            if (value) {
                [self setValue:value forKey:name];
            }
        }];
    }
    return self;
}

- (void)save
{
    [self checkTable];
    
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
//        NSString *type = [propertyInfos objectForKey:key];
        id value = [self valueForKey:key];
        [params addObject:value];
//        if ([type isEqualToString:DBInt]) {
//            [params addObject:value];
//        }else if ([type isEqualToString:DBFloat]){
//            [params addObject:value];
//        }else if ([type isEqualToString:DBText]){
//            [params addObject:value];
//        }else if ([type isEqualToString:DBData]){
//            [params addObject:value];
//        }
    }
    
    [[T8DataBaseManager shareInstance] dispatchOnDatabaseThread:^(FMDatabase *db) {
        [db executeUpdate:queryFormat withArgumentsInArray:params];
    } synchronous:false];
}

- (void)deleteObject
{
    NSString *primaryKey = [[self class] primaryKey];
    NSString *queryFormat = [NSString stringWithFormat:@"DELETE FROM %@ WHERE %@ = ?", [[self class] tableName], primaryKey];
    NSArray *valueArr = [NSArray arrayWithObject:[self valueForKey:primaryKey]];
    
    [[T8DataBaseManager shareInstance] dispatchOnDatabaseThread:^(FMDatabase *db) {
        [db executeUpdate:queryFormat withArgumentsInArray:valueArr];
    } synchronous:false];
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
                }else if ([type isEqualToString:DBData]){
                    value = [result dataForColumn:key];
                }
                [model setValue:value forKey:key];
            }];
            [resultArr addObject:model];
        }
        
    } synchronous:true];
    
    return resultArr;
}

- (void)checkTable
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
    
//    [[T8DataBaseManager shareInstance] dispatchOnDatabaseThread:^(FMDatabase *db) {
//        [db executeUpdate:[NSString stringWithFormat:@"drop table %@", [[self class] tableName]]];
//    } synchronous:true];
    
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
        unsigned int count;
        objc_property_t *properties = class_copyPropertyList([self class], &count);
        for (int i = 0; i < count; i++) {
            objc_property_t property = properties[i];
            NSString * key = [[NSString alloc]initWithCString:property_getName(property)  encoding:NSUTF8StringEncoding];
            NSString *type = [self dbTypeConvertFromObjc_property_t:property];
            [classDict setObject:type forKey:key];
        }
        [propertyInfoDict setObject:classDict forKey:className];
    }
    return classDict;
}

+ (NSString *)dbTypeConvertFromObjc_property_t:(objc_property_t)property
{
    char * type = property_copyAttributeValue(property, "T");
    
    switch(type[0]) {
        case 'f' : //float
        case 'd' : //double
        {
            return DBFloat;
        }
            break;
            
        case 'c':   // char
        case 's':   // short
        case 'i':   // int
        case 'l':   // long
        case 'q':   // NSInteger
        {
            return DBInt;
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
                return DBText;
            }
            
            if ([NSClassFromString(cls) isSubclassOfClass:[NSNumber class]]) {
                return DBText;
            }
            
            if ([NSClassFromString(cls) isSubclassOfClass:[NSDictionary class]]) {
                return DBText;
            }
            
            if ([NSClassFromString(cls) isSubclassOfClass:[NSArray class]]) {
                return DBText;
            }
            
            if ([NSClassFromString(cls) isSubclassOfClass:[NSDate class]]) {
                return DBText;
            }
            
            if ([NSClassFromString(cls) isSubclassOfClass:[NSData class]]) {
                return DBData;
            }
        }
            break;
    }
    
    return DBText;
}

/**
 *	@brief	获取自身的属性
 *
 *	@param 	pronames 	保存属性名称
 *	@param 	protypes 	保存属性类型
 */
+ (void)getSelfPropertys:(NSMutableArray *)pronames protypes:(NSMutableArray *)protypes
{
    unsigned int outCount, i;
    objc_property_t *properties = class_copyPropertyList(self, &outCount);
    for (i = 0; i < outCount; i++) {
        objc_property_t property = properties[i];
        NSString *propertyName = [NSString stringWithCString:property_getName(property) encoding:NSUTF8StringEncoding];
        if([propertyName isEqualToString:@"rowid"])
        {
            continue;
        }
        [pronames addObject:propertyName];
        NSString *propertyType = [NSString stringWithCString: property_getAttributes(property) encoding:NSUTF8StringEncoding];
        /*
         c char
         i int
         l long
         s short
         d double
         f float
         @ id //指针 对象
         ...  BOOL 获取到的表示 方式是 char
         .... ^i 表示  int*  一般都不会用到
         */
        NSLog(@"tttt:%@, %@", propertyName, propertyType);
        if ([propertyType hasPrefix:@"T@"]) {
            [protypes addObject:[propertyType substringWithRange:NSMakeRange(3, [propertyType rangeOfString:@","].location-4)]];
        }
        else if([propertyType hasPrefix:@"T{"])
        {
            [protypes addObject:[propertyType substringWithRange:NSMakeRange(2, [propertyType rangeOfString:@"="].location-2)]];
        }
        else
        {
            propertyType = [propertyType lowercaseString];
            if ([propertyType hasPrefix:@"ti"])
            {
                [protypes addObject:@"int"];
            }
            else if ([propertyType hasPrefix:@"tf"])
            {
                [protypes addObject:@"float"];
            }
            else if([propertyType hasPrefix:@"td"]) {
                [protypes addObject:@"double"];
            }
            else if([propertyType hasPrefix:@"tl"])
            {
                [protypes addObject:@"long"];
            }
            else if ([propertyType hasPrefix:@"tc"]) {
                [protypes addObject:@"char"];
            }
            else if([propertyType hasPrefix:@"ts"])
            {
                [protypes addObject:@"short"];
            }
            else {
                [protypes addObject:@"NSString"];
            }
        }
    }
    free(properties);
}

@end
