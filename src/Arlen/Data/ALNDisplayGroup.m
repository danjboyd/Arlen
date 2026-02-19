#import "ALNDisplayGroup.h"

#import "ALNSQLBuilder.h"

@interface ALNDisplayGroup ()

@property(nonatomic, strong, readwrite) id<ALNDatabaseAdapter> adapter;
@property(nonatomic, copy, readwrite) NSString *tableName;
@property(nonatomic, strong) NSMutableDictionary *mutableFilters;
@property(nonatomic, strong) NSMutableArray *mutableSortOrder;
@property(nonatomic, strong) NSArray *mutableObjects;

@end

@implementation ALNDisplayGroup

- (instancetype)initWithAdapter:(id<ALNDatabaseAdapter>)adapter
                      tableName:(NSString *)tableName {
  self = [super init];
  if (self) {
    _adapter = adapter;
    _tableName = [tableName copy] ?: @"";
    _fetchFields = @[ @"*" ];
    _batchSize = 25;
    _batchIndex = 0;
    _mutableFilters = [NSMutableDictionary dictionary];
    _mutableSortOrder = [NSMutableArray array];
    _mutableObjects = @[];
  }
  return self;
}

- (NSDictionary *)filters {
  return [NSDictionary dictionaryWithDictionary:self.mutableFilters];
}

- (NSArray *)sortOrder {
  return [NSArray arrayWithArray:self.mutableSortOrder];
}

- (NSArray<NSDictionary *> *)objects {
  return [NSArray arrayWithArray:self.mutableObjects ?: @[]];
}

- (void)setFilterValue:(id)value forField:(NSString *)field {
  if ([field length] == 0) {
    return;
  }
  if (value == nil || value == [NSNull null]) {
    [self.mutableFilters removeObjectForKey:field];
    return;
  }
  self.mutableFilters[field] = value;
}

- (void)removeFilterForField:(NSString *)field {
  if ([field length] == 0) {
    return;
  }
  [self.mutableFilters removeObjectForKey:field];
}

- (void)clearFilters {
  [self.mutableFilters removeAllObjects];
}

- (void)addSortField:(NSString *)field descending:(BOOL)descending {
  if ([field length] == 0) {
    return;
  }
  [self.mutableSortOrder addObject:@{
    @"field" : field,
    @"descending" : @(descending)
  }];
}

- (void)clearSortOrder {
  [self.mutableSortOrder removeAllObjects];
}

- (BOOL)fetch:(NSError **)error {
  if (self.adapter == nil) {
    if (error != NULL) {
      *error = ALNDatabaseAdapterMakeError(ALNDatabaseAdapterErrorInvalidArgument,
                                           @"display group adapter is required",
                                           nil);
    }
    return NO;
  }
  if ([self.tableName length] == 0) {
    if (error != NULL) {
      *error = ALNDatabaseAdapterMakeError(ALNDatabaseAdapterErrorInvalidArgument,
                                           @"display group table name is required",
                                           nil);
    }
    return NO;
  }

  ALNSQLBuilder *builder = [ALNSQLBuilder selectFrom:self.tableName
                                             columns:([self.fetchFields count] > 0 ? self.fetchFields : @[ @"*" ])];

  NSArray *filterKeys =
      [[self.mutableFilters allKeys] sortedArrayUsingSelector:@selector(compare:)];
  for (NSString *key in filterKeys) {
    [builder whereField:key equals:self.mutableFilters[key]];
  }

  for (NSDictionary *entry in self.mutableSortOrder) {
    NSString *field = [entry[@"field"] isKindOfClass:[NSString class]] ? entry[@"field"] : @"";
    BOOL descending = [entry[@"descending"] boolValue];
    [builder orderByField:field descending:descending];
  }

  NSUInteger size = (self.batchSize > 0) ? self.batchSize : 25;
  [builder limit:size];
  [builder offset:(self.batchIndex * size)];

  NSDictionary *built = [builder build:error];
  if (built == nil) {
    return NO;
  }

  NSArray *rows = [self.adapter executeQuery:built[@"sql"]
                                  parameters:built[@"parameters"]
                                       error:error];
  if (rows == nil) {
    return NO;
  }
  self.mutableObjects = [NSArray arrayWithArray:rows];
  return YES;
}

@end
