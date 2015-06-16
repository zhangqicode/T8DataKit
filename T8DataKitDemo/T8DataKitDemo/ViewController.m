//
//  ViewController.m
//  T8DataKitDemo
//
//  Created by 琦张 on 15/6/1.
//  Copyright (c) 2015年 琦张. All rights reserved.
//

#import "ViewController.h"
#import "T8TestModel.h"

@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    T8TestModel *model = [[T8TestModel alloc] init];
    model.name = @"123";
    model.age = 20;
    [model save];
    
    T8TestModel *query = [T8TestModel queryWithCondition:@"WHERE name = '123'"].firstObject;
    NSLog(@"121...");
    
    NSDictionary *dict = [NSDictionary dictionaryWithObjectsAndKeys:@"zhangqi", @"name", @(26), @"age", nil];
    T8TestModel *zhang = [[T8TestModel alloc] initWithDict:dict];
    NSLog(@"1212222...");

    
    // Do any additional setup after loading the view, typically from a nib.
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end
