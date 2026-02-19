#import "ALNPageState.h"

#import "ALNContext.h"

static NSString *const ALNPageStateSessionRootKey = @"_aln_page_state";
static NSString *const ALNPageStateTransientRootKey = @"aln.page_state.transient";

@interface ALNPageState ()

@property(nonatomic, assign) ALNContext *context;
@property(nonatomic, copy, readwrite) NSString *pageKey;

@end

@implementation ALNPageState

- (instancetype)initWithContext:(ALNContext *)context
                        pageKey:(NSString *)pageKey {
  self = [super init];
  if (self) {
    _context = context;
    _pageKey = ([pageKey length] > 0) ? [pageKey copy] : @"default";
  }
  return self;
}

- (NSMutableDictionary *)mutablePageStateRoot {
  BOOL enabled = [self.context.stash[ALNContextPageStateEnabledStashKey] boolValue];
  NSMutableDictionary *container = nil;
  NSString *rootKey = nil;
  if (enabled) {
    container = [self.context session];
    rootKey = ALNPageStateSessionRootKey;
  } else {
    container = self.context.stash;
    rootKey = ALNPageStateTransientRootKey;
  }

  id root = container[rootKey];
  if ([root isKindOfClass:[NSMutableDictionary class]]) {
    return root;
  }
  if ([root isKindOfClass:[NSDictionary class]]) {
    NSMutableDictionary *copy = [NSMutableDictionary dictionaryWithDictionary:root];
    container[rootKey] = copy;
    return copy;
  }
  NSMutableDictionary *created = [NSMutableDictionary dictionary];
  container[rootKey] = created;
  return created;
}

- (NSMutableDictionary *)mutablePageDictionary {
  NSMutableDictionary *root = [self mutablePageStateRoot];
  id page = root[self.pageKey];
  if ([page isKindOfClass:[NSMutableDictionary class]]) {
    return page;
  }
  if ([page isKindOfClass:[NSDictionary class]]) {
    NSMutableDictionary *copy = [NSMutableDictionary dictionaryWithDictionary:page];
    root[self.pageKey] = copy;
    return copy;
  }
  NSMutableDictionary *created = [NSMutableDictionary dictionary];
  root[self.pageKey] = created;
  return created;
}

- (NSDictionary *)allValues {
  return [NSDictionary dictionaryWithDictionary:[self mutablePageDictionary]];
}

- (id)valueForKey:(NSString *)key {
  if ([key length] == 0) {
    return nil;
  }
  return [self mutablePageDictionary][key];
}

- (void)setValue:(id)value forKey:(NSString *)key {
  if ([key length] == 0) {
    return;
  }
  NSMutableDictionary *page = [self mutablePageDictionary];
  if (value == nil) {
    [page removeObjectForKey:key];
  } else {
    page[key] = value;
  }
  if ([self.context.stash[ALNContextPageStateEnabledStashKey] boolValue]) {
    [self.context markSessionDirty];
  }
}

- (void)clear {
  NSMutableDictionary *root = [self mutablePageStateRoot];
  [root removeObjectForKey:self.pageKey];
  if ([self.context.stash[ALNContextPageStateEnabledStashKey] boolValue]) {
    [self.context markSessionDirty];
  }
}

@end
