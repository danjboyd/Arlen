#import "ALNORMFieldDescriptor.h"

@implementation ALNORMFieldDescriptor

- (instancetype)init {
  return [self initWithName:@""
               propertyName:@""
                 columnName:@""
                   dataType:@"text"
                   objcType:@"id"
           runtimeClassName:nil
          propertyAttribute:@"strong"
                    ordinal:0
                   nullable:YES
                 primaryKey:NO
                     unique:NO
                 hasDefault:NO
                   readOnly:NO
          defaultValueShape:@"none"];
}

- (instancetype)initWithName:(NSString *)name
                propertyName:(NSString *)propertyName
                  columnName:(NSString *)columnName
                    dataType:(NSString *)dataType
                    objcType:(NSString *)objcType
            runtimeClassName:(NSString *)runtimeClassName
           propertyAttribute:(NSString *)propertyAttribute
                     ordinal:(NSInteger)ordinal
                    nullable:(BOOL)nullable
                  primaryKey:(BOOL)primaryKey
                      unique:(BOOL)unique
                  hasDefault:(BOOL)hasDefault
                    readOnly:(BOOL)readOnly
           defaultValueShape:(NSString *)defaultValueShape {
  self = [super init];
  if (self != nil) {
    _name = [name copy] ?: @"";
    _propertyName = [propertyName copy] ?: @"";
    _columnName = [columnName copy] ?: @"";
    _dataType = [dataType copy] ?: @"text";
    _objcType = [objcType copy] ?: @"id";
    _runtimeClassName = [runtimeClassName copy] ?: @"";
    _propertyAttribute = [propertyAttribute copy] ?: @"strong";
    _ordinal = ordinal;
    _nullable = nullable;
    _primaryKey = primaryKey;
    _unique = unique;
    _hasDefault = hasDefault;
    _readOnly = readOnly;
    _defaultValueShape = [defaultValueShape copy] ?: @"none";
  }
  return self;
}

- (NSDictionary<NSString *,id> *)dictionaryRepresentation {
  return @{
    @"name" : self.name ?: @"",
    @"property_name" : self.propertyName ?: @"",
    @"column_name" : self.columnName ?: @"",
    @"data_type" : self.dataType ?: @"",
    @"objc_type" : self.objcType ?: @"",
    @"runtime_class_name" : self.runtimeClassName ?: @"",
    @"property_attribute" : self.propertyAttribute ?: @"",
    @"ordinal" : @(self.ordinal),
    @"nullable" : @(self.isNullable),
    @"primary_key" : @(self.isPrimaryKey),
    @"unique" : @(self.isUnique),
    @"has_default" : @(self.hasDefaultValue),
    @"read_only" : @(self.isReadOnly),
    @"default_value_shape" : self.defaultValueShape ?: @"none",
  };
}

@end
