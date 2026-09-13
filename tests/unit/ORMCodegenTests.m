#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import <dlfcn.h>
#import <objc/runtime.h>

#import "../shared/ALNTestSupport.h"
#import "ArlenORM/ArlenORM.h"

@interface ReservedRuntimePublicReservedModel : ALNORMModel
@property(nonatomic, copy) NSString *stateValue3;
@property(nonatomic, copy) NSString *descriptionValue;
@property(nonatomic, copy) NSString *displayName;
@end

@interface ORMCodegenTests : XCTestCase
@end

@implementation ORMCodegenTests

- (NSString *)syntaxOnlyIncludeFlagsWithRepoRoot:(NSString *)repoRoot temporaryDir:(NSString *)tmpDir {
  NSMutableArray<NSString *> *flags = [NSMutableArray array];
  NSArray<NSString *> *gnustepHeaderRoots = @[
    [NSHomeDirectory() stringByAppendingPathComponent:@"GNUstep/Library/Headers"],
    @"/usr/GNUstep/Local/Library/Headers",
    @"/usr/GNUstep/System/Library/Headers",
  ];
  for (NSString *headerRoot in gnustepHeaderRoots) {
    BOOL isDirectory = NO;
    if ([[NSFileManager defaultManager] fileExistsAtPath:headerRoot isDirectory:&isDirectory] &&
        isDirectory) {
      [flags addObject:[NSString stringWithFormat:@"-I%@", ALNTestShellQuote(headerRoot)]];
    }
  }
  NSArray<NSString *> *includePaths = @[
    tmpDir ?: @"",
    [repoRoot stringByAppendingPathComponent:@"src"],
    [repoRoot stringByAppendingPathComponent:@"src/Arlen"],
    [repoRoot stringByAppendingPathComponent:@"src/Arlen/Core"],
    [repoRoot stringByAppendingPathComponent:@"src/Arlen/Data"],
    [repoRoot stringByAppendingPathComponent:@"src/Arlen/HTTP"],
    [repoRoot stringByAppendingPathComponent:@"src/Arlen/MVC/Controller"],
    [repoRoot stringByAppendingPathComponent:@"src/Arlen/MVC/Middleware"],
    [repoRoot stringByAppendingPathComponent:@"src/Arlen/MVC/Routing"],
    [repoRoot stringByAppendingPathComponent:@"src/Arlen/MVC/Template"],
    [repoRoot stringByAppendingPathComponent:@"src/Arlen/MVC/View"],
    [repoRoot stringByAppendingPathComponent:@"src/Arlen/Support"],
    [repoRoot stringByAppendingPathComponent:@"src/Arlen/Support/third_party/argon2/include"],
    [repoRoot stringByAppendingPathComponent:@"src/Arlen/Support/third_party/argon2/src"],
    [repoRoot stringByAppendingPathComponent:@"src/MojoObjc"],
    [repoRoot stringByAppendingPathComponent:@"src/MojoObjc/Core"],
    [repoRoot stringByAppendingPathComponent:@"src/MojoObjc/Data"],
    [repoRoot stringByAppendingPathComponent:@"src/MojoObjc/HTTP"],
    [repoRoot stringByAppendingPathComponent:@"src/MojoObjc/MVC/Controller"],
    [repoRoot stringByAppendingPathComponent:@"src/MojoObjc/MVC/Middleware"],
    [repoRoot stringByAppendingPathComponent:@"src/MojoObjc/MVC/Routing"],
    [repoRoot stringByAppendingPathComponent:@"src/MojoObjc/MVC/Template"],
    [repoRoot stringByAppendingPathComponent:@"src/MojoObjc/MVC/View"],
    [repoRoot stringByAppendingPathComponent:@"src/MojoObjc/Support"],
  ];
  for (NSString *includePath in includePaths) {
    [flags addObject:[NSString stringWithFormat:@"-I%@", ALNTestShellQuote(includePath)]];
  }
  NSString *modulesRoot = [repoRoot stringByAppendingPathComponent:@"modules"];
  NSArray<NSString *> *moduleNames =
      [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:modulesRoot error:NULL]
          sortedArrayUsingSelector:@selector(compare:)];
  for (NSString *moduleName in moduleNames) {
    NSString *sourcesPath = [modulesRoot stringByAppendingPathComponent:[moduleName stringByAppendingPathComponent:@"Sources"]];
    BOOL isDirectory = NO;
    if ([[NSFileManager defaultManager] fileExistsAtPath:sourcesPath isDirectory:&isDirectory] && isDirectory) {
      [flags addObject:[NSString stringWithFormat:@"-I%@", ALNTestShellQuote(sourcesPath)]];
    }
  }
  [flags addObject:@"-I/usr/include/postgresql"];
  return [flags componentsJoinedByString:@" "];
}

- (NSString *)gnuStepSyntaxOnlyContractFlags {
  return @"-fobjc-runtime=gnustep-2.2 -fblocks -D_NATIVE_OBJC_EXCEPTIONS "
         "-fconstant-string-class=NSConstantString";
}

- (NSDictionary *)fixture {
  NSError *error = nil;
  NSDictionary *fixture =
      ALNTestJSONDictionaryAtRelativePath(@"tests/fixtures/phase26/orm_schema_metadata_contract.json", &error);
  XCTAssertNil(error);
  XCTAssertNotNil(fixture);
  return fixture ?: @{};
}

- (NSDictionary *)fixtureMetadata {
  NSDictionary *fixture = [self fixture];
  NSDictionary *metadata = [fixture[@"metadata"] isKindOfClass:[NSDictionary class]] ? fixture[@"metadata"] : @{};
  return metadata;
}

- (NSDictionary *)reversedMetadata {
  NSDictionary *metadata = [self fixtureMetadata];
  NSMutableDictionary *reversed = [metadata mutableCopy];
  for (NSString *key in @[ @"relations", @"columns", @"primary_keys", @"unique_constraints", @"foreign_keys" ]) {
    NSArray *items = [metadata[key] isKindOfClass:[NSArray class]] ? metadata[key] : @[];
    reversed[key] = [[items reverseObjectEnumerator] allObjects];
  }
  return reversed;
}

- (ALNORMModelDescriptor *)descriptorNamed:(NSString *)entityName
                             inDescriptors:(NSArray<ALNORMModelDescriptor *> *)descriptors {
  for (ALNORMModelDescriptor *descriptor in descriptors) {
    if ([descriptor.entityName isEqualToString:entityName]) {
      return descriptor;
    }
  }
  return nil;
}

- (void)testDescriptorsReflectAssociationsAndReadOnlySemantics {
  NSError *error = nil;
  NSArray<ALNORMModelDescriptor *> *descriptors =
      [ALNORMCodegen modelDescriptorsFromSchemaMetadata:[self fixtureMetadata]
                                            classPrefix:@"ALNORMX"
                                                  error:&error];
  XCTAssertNil(error);
  XCTAssertEqual((NSUInteger)6, [descriptors count]);

  ALNORMModelDescriptor *users = [self descriptorNamed:@"public.users" inDescriptors:descriptors];
  ALNORMModelDescriptor *profiles = [self descriptorNamed:@"public.profiles" inDescriptors:descriptors];
  ALNORMModelDescriptor *posts = [self descriptorNamed:@"public.posts" inDescriptors:descriptors];
  ALNORMModelDescriptor *tags = [self descriptorNamed:@"public.tags" inDescriptors:descriptors];
  ALNORMModelDescriptor *userEmails = [self descriptorNamed:@"public.user_emails" inDescriptors:descriptors];

  XCTAssertNotNil(users);
  XCTAssertNotNil(profiles);
  XCTAssertNotNil(posts);
  XCTAssertNotNil(tags);
  XCTAssertNotNil(userEmails);

  XCTAssertEqualObjects(@"ALNORMXPublicUsersModel", users.className);
  XCTAssertEqualObjects((NSArray<NSString *> *)@[ @"id" ], users.primaryKeyFieldNames);
  XCTAssertTrue([users hasUniqueConstraintForFieldSet:@[ @"email" ]]);

  XCTAssertEqualObjects(@"belongs_to", [[profiles relationNamed:@"user"] kindName]);
  XCTAssertEqualObjects(@"public.users", [[profiles relationNamed:@"user"] targetEntityName]);

  XCTAssertEqualObjects(@"has_one", [[users relationNamed:@"profile"] kindName]);
  XCTAssertEqualObjects(@"public.profiles", [[users relationNamed:@"profile"] targetEntityName]);

  XCTAssertEqualObjects(@"has_many", [[users relationNamed:@"posts"] kindName]);
  XCTAssertEqualObjects(@"public.posts", [[users relationNamed:@"posts"] targetEntityName]);

  ALNORMRelationDescriptor *postsTags = [posts relationNamed:@"tags"];
  XCTAssertNotNil(postsTags);
  XCTAssertEqualObjects(@"many_to_many", [postsTags kindName]);
  XCTAssertEqualObjects(@"public.post_tags", postsTags.throughEntityName);
  XCTAssertEqualObjects((NSArray<NSString *> *)@[ @"position" ], postsTags.pivotFieldNames);

  ALNORMRelationDescriptor *tagsPosts = [tags relationNamed:@"posts"];
  XCTAssertNotNil(tagsPosts);
  XCTAssertEqualObjects(@"many_to_many", [tagsPosts kindName]);
  XCTAssertEqualObjects(@"public.post_tags", tagsPosts.throughEntityName);

  XCTAssertTrue(userEmails.isReadOnly);
  XCTAssertEqualObjects(@"view", userEmails.relationKind);
}

- (void)testRenderArtifactsAreDeterministicAndVersioned {
  NSError *firstError = nil;
  NSDictionary *first = [ALNORMCodegen renderArtifactsFromSchemaMetadata:[self fixtureMetadata]
                                                             classPrefix:@"ALNORMX"
                                                                   error:&firstError];
  XCTAssertNil(firstError);
  XCTAssertNotNil(first);

  NSError *secondError = nil;
  NSDictionary *second = [ALNORMCodegen renderArtifactsFromSchemaMetadata:[self reversedMetadata]
                                                              classPrefix:@"ALNORMX"
                                                                    error:&secondError];
  XCTAssertNil(secondError);
  XCTAssertNotNil(second);

  XCTAssertEqualObjects(first[@"baseName"], @"ALNORMXGeneratedModels");
  XCTAssertEqualObjects(first[@"header"], second[@"header"]);
  XCTAssertEqualObjects(first[@"implementation"], second[@"implementation"]);
  XCTAssertEqualObjects(first[@"manifest"], second[@"manifest"]);
  XCTAssertEqualObjects(first[@"modelCount"], @6);

  NSString *header = [first[@"header"] isKindOfClass:[NSString class]] ? first[@"header"] : @"";
  NSString *implementation =
      [first[@"implementation"] isKindOfClass:[NSString class]] ? first[@"implementation"] : @"";
  NSString *manifest = [first[@"manifest"] isKindOfClass:[NSString class]] ? first[@"manifest"] : @"";

  XCTAssertTrue([header containsString:@"@interface ALNORMXPublicUsersModel : ALNORMModel"]);
  XCTAssertTrue([header containsString:@"@interface ALNORMXPublicUserEmailsModel : ALNORMModel"]);
  XCTAssertTrue([header containsString:@"@property(nonatomic, copy, readonly, nullable) NSString * email;"]);
  XCTAssertTrue([implementation containsString:@"return @\"view\";"]);
  NSRange viewSectionStart = [implementation rangeOfString:@"@implementation ALNORMXPublicUserEmailsModel"];
  XCTAssertNotEqual(NSNotFound, viewSectionStart.location);
  NSRange viewSectionEnd = [implementation rangeOfString:@"@end"
                                                 options:0
                                                   range:NSMakeRange(viewSectionStart.location,
                                                                     [implementation length] - viewSectionStart.location)];
  XCTAssertNotEqual(NSNotFound, viewSectionEnd.location);
  NSString *viewSection =
      [implementation substringWithRange:NSMakeRange(viewSectionStart.location,
                                                     NSMaxRange(viewSectionEnd) - viewSectionStart.location)];
  XCTAssertFalse([viewSection containsString:@"setEmail:"]);
  XCTAssertTrue([manifest length] > 0);
}

- (void)testDescriptorOverridesCanReplaceInferredRelations {
  NSDictionary *overrides = @{
    @"public.users" : @{
      @"relations" : @[
        @{
          @"kind" : @"has_many",
          @"name" : @"articles",
          @"target_entity_name" : @"public.posts",
          @"source_field_names" : @[ @"id" ],
          @"target_field_names" : @[ @"userId" ],
          @"read_only" : @NO,
        },
      ],
    },
  };

  NSError *error = nil;
  NSArray<ALNORMModelDescriptor *> *descriptors =
      [ALNORMCodegen modelDescriptorsFromSchemaMetadata:[self fixtureMetadata]
                                            classPrefix:@"ALNORMX"
                                         databaseTarget:nil
                                     descriptorOverrides:overrides
                                                  error:&error];
  XCTAssertNil(error);
  ALNORMModelDescriptor *users = [self descriptorNamed:@"public.users" inDescriptors:descriptors];
  XCTAssertNotNil(users);
  XCTAssertEqual((NSUInteger)1, [users.relations count]);
  XCTAssertEqualObjects(@"articles", [users.relations[0] name]);
  XCTAssertEqualObjects(@"has_many", [[users.relations[0] kindName] lowercaseString]);
  XCTAssertFalse([users.relations[0] isInferred]);
}

- (NSDictionary *)reservedMetadata {
  NSError *error = nil;
  NSDictionary *metadata = ALNTestJSONDictionaryAtRelativePath(@"tests/fixtures/phase26/orm_reserved_names.json", &error);
  XCTAssertNil(error);
  return metadata;
}

- (void)testReservedPropertyNamesAndOverrides {
  NSDictionary *metadata = [self reservedMetadata];
  NSError *error = nil;
  NSArray *models = [ALNORMCodegen modelDescriptorsFromSchemaMetadata:metadata classPrefix:@"Reserved" error:&error];
  XCTAssertNil(error);
  ALNORMModelDescriptor *model = [models firstObject];
  NSDictionary *expected = @{ @"State": @"stateValue3", @"Description": @"descriptionValue",
      @"class": @"classValue", @"hash": @"hashValue", @"context": @"contextValue",
      @"descriptor": @"descriptorValue", @"field_values": @"fieldValuesValue",
      @"new": @"fieldNew", @"copy": @"fieldCopy", @"init": @"fieldInit" };
  for (NSString *column in expected) {
    ALNORMFieldDescriptor *field = [model fieldForColumnName:column];
    XCTAssertEqualObjects(expected[column], field.propertyName);
    XCTAssertEqualObjects(field, [model fieldForPropertyName:expected[column]]);
  }
  XCTAssertEqualObjects(@"state", [model fieldForColumnName:@"State"].name);
  XCTAssertEqualObjects((@[@"state"]), [model relationNamed:@"target"].sourceFieldNames);
  NSDictionary *overrides = @{ @"public.reserved": @{ @"property_names": @{ @"State": @"taxState" } } };
  models = [ALNORMCodegen modelDescriptorsFromSchemaMetadata:metadata classPrefix:@"Reserved"
      databaseTarget:nil descriptorOverrides:overrides error:&error];
  XCTAssertNil(error);
  XCTAssertEqualObjects(@"taxState", [[models firstObject] fieldForColumnName:@"State"].propertyName);
  for (NSDictionary *mapping in @[ @{ @"State": @"state" }, @{ @"State": @"context" },
      @{ @"State": @"stateValue" }, @{ @"State": @"newThing" }, @{ @"State": @"bad-name" },
      @{ @"missing": @"safeName" }, @{ @"State": @"same", @"Description": @"Same" } ]) {
    error = nil;
    models = [ALNORMCodegen modelDescriptorsFromSchemaMetadata:metadata classPrefix:@"Reserved"
        databaseTarget:nil descriptorOverrides:@{ @"public.reserved": @{ @"property_names": mapping } } error:&error];
    XCTAssertNil(models);
    XCTAssertNotNil(error);
    XCTAssertEqualObjects(@"public.reserved", error.userInfo[@"entity_name"]);
  }
  NSMutableDictionary *reversed = [metadata mutableCopy];
  reversed[@"columns"] = [metadata[@"columns"] reverseObjectEnumerator].allObjects;
  XCTAssertEqualObjects([ALNORMCodegen renderArtifactsFromSchemaMetadata:metadata classPrefix:@"Reserved" error:NULL],
                       [ALNORMCodegen renderArtifactsFromSchemaMetadata:reversed classPrefix:@"Reserved" error:NULL]);
  NSMutableArray *columns = [metadata[@"columns"] mutableCopy];
  [columns addObject:@{ @"schema": @"public", @"table": @"reserved", @"column": @"STATE", @"data_type": @"text" }];
  reversed[@"columns"] = columns;
  XCTAssertNil([ALNORMCodegen renderArtifactsFromSchemaMetadata:reversed classPrefix:@"Reserved" error:&error]);
  XCTAssertNotNil(error);
}

- (void)testReservedContractCoversORMBaseAccessors {
  unsigned int count = 0;
  Method *methods = class_copyMethodList([ALNORMModel class], &count);
  for (unsigned int index = 0; index < count; index++) {
    NSString *selector = NSStringFromSelector(method_getName(methods[index]));
    if ([selector hasPrefix:@"."]) continue;
    NSString *property = selector;
    if ([selector containsString:@":"]) {
      if (![selector hasPrefix:@"set"] || ![selector hasSuffix:@":"] ||
          [[selector componentsSeparatedByString:@":"] count] != 2) continue;
      property = [selector substringWithRange:NSMakeRange(3, selector.length - 4)];
      property = [NSString stringWithFormat:@"%@%@", [[property substringToIndex:1] lowercaseString],
                                             [property substringFromIndex:1]];
    }
    NSError *error = nil;
    NSDictionary *overrides = @{ @"public.reserved": @{ @"property_names": @{ @"State": property } } };
    XCTAssertNil([ALNORMCodegen renderArtifactsFromSchemaMetadata:[self reservedMetadata]
        classPrefix:@"Reserved" databaseTarget:nil descriptorOverrides:overrides error:&error], @"%@", selector);
    XCTAssertNotNil(error, @"%@", selector);
  }
  free(methods);
}

- (void)testGeneratedHelperCollisionsAreRejected {
  NSError *error = nil;
  NSDictionary *overrides = @{ @"public.reserved": @{ @"relations": @[
      @{ @"name": @"someTarget", @"kind": @"belongs_to", @"target_entity_name": @"public.targets" },
      @{ @"name": @"sometarget", @"kind": @"belongs_to", @"target_entity_name": @"public.targets" }
  ] } };
  XCTAssertNil([ALNORMCodegen renderArtifactsFromSchemaMetadata:[self reservedMetadata]
      classPrefix:@"Reserved" databaseTarget:nil descriptorOverrides:overrides error:&error]);
  XCTAssertEqualObjects(@"relationSometarget", error.userInfo[@"selector"]);
}

- (void)testReservedGeneratedModelsCompileAndPreserveRuntimeBehavior {
  NSError *error = nil;
  NSDictionary *artifacts = [ALNORMCodegen renderArtifactsFromSchemaMetadata:[self reservedMetadata]
      classPrefix:@"ReservedRuntime" error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(artifacts);
  if (artifacts == nil) return;
  NSString *tmp = ALNTestTemporaryDirectory(@"orm_reserved_runtime");
  NSString *header = [tmp stringByAppendingPathComponent:@"ReservedRuntimeGeneratedModels.h"];
  NSString *implementation = [tmp stringByAppendingPathComponent:@"ReservedRuntimeGeneratedModels.m"];
  NSString *library = [tmp stringByAppendingPathComponent:@"reserved.so"];
  XCTAssertTrue(ALNTestWriteUTF8File(header, artifacts[@"header"], &error));
  XCTAssertTrue(ALNTestWriteUTF8File(implementation, artifacts[@"implementation"], &error));
  NSString *root = ALNTestRepoRoot();
  NSString *flags = [self syntaxOnlyIncludeFlagsWithRepoRoot:root temporaryDir:tmp];
#if defined(__APPLE__)
  NSString *compiler = @"xcrun clang -fobjc-arc -bundle -undefined dynamic_lookup";
#else
  NSString *compiler = [NSString stringWithFormat:@"%@ && clang $(gnustep-config --objc-flags) -fobjc-arc -shared -fPIC", ALNTestGNUstepSourceCommandForRepoRoot(root)];
#endif
  NSString *command = [NSString stringWithFormat:@"cd %@ && %@ -Werror=incompatible-property-type -Werror=property-attribute-mismatch -Werror=nullability -Wno-nullability-completeness %@ %@ -o %@",
      ALNTestShellQuote(tmp), compiler, flags, ALNTestShellQuote(implementation), ALNTestShellQuote(library)];
  int exitCode = 0;
  NSString *output = ALNTestRunShellCapture(command, &exitCode);
  XCTAssertEqual(0, exitCode, @"%@", output);
  if (exitCode != 0) return;
  // Objective-C classes remain registered for the test process lifetime.
  NSString *testBinary = [[NSBundle bundleForClass:[self class]] executablePath];
  void *testHandle = dlopen([testBinary fileSystemRepresentation], RTLD_NOW | RTLD_GLOBAL);
  XCTAssertTrue(testHandle != NULL);
  void *handle = dlopen([library fileSystemRepresentation], RTLD_NOW | RTLD_GLOBAL);
  XCTAssertTrue(handle != NULL, @"%s", dlerror());
  if (handle == NULL) return;
  Class cls = NSClassFromString(@"ReservedRuntimePublicReservedModel");
  XCTAssertTrue([cls isSubclassOfClass:[ALNORMModel class]]);
  ReservedRuntimePublicReservedModel *model = [cls modelFromRow:@{ @"id": @"1", @"State": @"Ohio", @"Description": @"Example" } error:&error];
  XCTAssertNotNil(model);
  XCTAssertNil(error);
  XCTAssertEqual(ALNORMModelStateLoaded, model.state);
  XCTAssertEqualObjects(@"Ohio", model.stateValue3);
  XCTAssertEqualObjects(@"Example", model.descriptionValue);
  XCTAssertEqualObjects(@"Ohio", [model objectForColumnName:@"State"]);
  XCTAssertEqualObjects(@"Ohio", [model objectForFieldName:@"state"]);
  XCTAssertNotNil(model.descriptor);
  XCTAssertNil(model.context);
  model.stateValue3 = @"Maine";
  model.displayName = @"Display";
  XCTAssertEqual(ALNORMModelStateDirty, model.state);
  XCTAssertTrue([model.dirtyFieldNames containsObject:@"state"]);
  XCTAssertEqualObjects(@"Maine", [model objectForColumnName:@"State"]);
  XCTAssertEqualObjects(@"Display", [model objectForColumnName:@"display_name"]);
  [model markClean];
  XCTAssertEqual(ALNORMModelStateLoaded, model.state);
  XCTAssertEqual((NSUInteger)0, model.dirtyFieldNames.count);
  ALNORMModel *target = [NSClassFromString(@"ReservedRuntimePublicTargetsModel") modelFromRow:@{ @"id": @"Maine" } error:&error];
  XCTAssertTrue([model markRelationLoaded:@"target" value:target pivotRows:nil error:&error]);
  XCTAssertNil(error);
  XCTAssertTrue([model isRelationLoaded:@"target"]);
  XCTAssertEqualObjects(target, [model relationObjectForName:@"target"]);
  XCTAssertEqualObjects(@"Maine", model.stateValue3);
  XCTAssertEqual(ALNORMModelStateLoaded, model.state);
  [model markDetached];
  XCTAssertEqual(ALNORMModelStateDetached, model.state);
}

- (void)testQuotedPhysicalNamesAndAliasCollisions {
  NSError *error = nil;
  NSDictionary *metadata = ALNTestJSONDictionaryAtRelativePath(@"tests/fixtures/phase26/orm_quoted_identifiers.json", &error);
  NSArray *models = [ALNORMCodegen modelDescriptorsFromSchemaMetadata:metadata classPrefix:@"Quoted" error:&error];
  XCTAssertNil(error);
  ALNORMModelDescriptor *model = [models firstObject];
  XCTAssertEqualObjects(@"targetId", [model fieldForColumnName:@"Target ID"].propertyName);
  XCTAssertEqualObjects(@"stateValue", [model fieldForColumnName:@"State"].propertyName);
  XCTAssertEqualObjects(@"unitWellNotes", [model fieldForColumnName:@"Unit/Well Notes"].propertyName);
  XCTAssertEqualObjects(@" leading ", [model fieldForPropertyName:@"leading"].columnName);
  NSMutableDictionary *reversed = [metadata mutableCopy];
  reversed[@"columns"] = [metadata[@"columns"] reverseObjectEnumerator].allObjects;
  XCTAssertEqualObjects([ALNORMCodegen renderArtifactsFromSchemaMetadata:metadata classPrefix:@"Quoted" error:NULL],
                       [ALNORMCodegen renderArtifactsFromSchemaMetadata:reversed classPrefix:@"Quoted" error:NULL]);
  NSMutableArray *columns = [metadata[@"columns"] mutableCopy];
  [columns addObject:@{ @"schema": @"ot", @"table": @"CompulsoryUnitProjects", @"column": @"Unit_Name", @"data_type": @"text" }];
  reversed[@"columns"] = columns;
  XCTAssertNil([ALNORMCodegen modelDescriptorsFromSchemaMetadata:reversed classPrefix:@"Quoted" error:&error]);
  XCTAssertEqual(ALNORMErrorIdentifierCollision, error.code);
  error = nil;
  models = [ALNORMCodegen modelDescriptorsFromSchemaMetadata:reversed classPrefix:@"Quoted" databaseTarget:nil
      descriptorOverrides:@{ @"ot.CompulsoryUnitProjects": @{
          @"field_names": @{ @"Unit_Name": @"alternateUnitName" },
          @"property_names": @{ @"Target ID": @"legacyId" } } } error:&error];
  XCTAssertNil(error);
  model = [models firstObject];
  XCTAssertEqualObjects(@"Target ID", [model fieldForPropertyName:@"legacyId"].columnName);
  XCTAssertEqualObjects(@"Unit_Name", [model fieldNamed:@"alternateUnitName"].columnName);
  unichar nul = 0;
  NSMutableDictionary *badColumn = [columns[0] mutableCopy];
  badColumn[@"column"] = [NSString stringWithCharacters:&nul length:1];
  reversed[@"columns"] = @[ badColumn ];
  XCTAssertNil([ALNORMCodegen modelDescriptorsFromSchemaMetadata:reversed classPrefix:@"Quoted" error:&error]);
}

- (void)testQuotedGeneratedArtifactsCompileSyntaxOnly {
  [self assertGeneratedArtifactsCompile:[ALNTestJSONDictionaryAtRelativePath(@"tests/fixtures/phase26/orm_quoted_identifiers.json", NULL) copy]];
}

- (void)testQuotedSchemaAndTableNamesCompile {
  NSMutableDictionary *metadata = [[self reservedMetadata] mutableCopy];
  for (NSString *collection in @[@"relations", @"columns", @"primary_keys", @"unique_constraints", @"foreign_keys"]) {
    NSMutableArray *rows = [NSMutableArray array];
    for (NSDictionary *raw in metadata[collection] ?: @[]) {
      NSMutableDictionary *row = [raw mutableCopy];
      row[@"schema"] = @"Legacy.Schema";
      row[@"table"] = [row[@"table"] stringByAppendingString:@" \"Table\""];
      if (row[@"referenced_schema"]) row[@"referenced_schema"] = @"Legacy.Schema";
      if (row[@"referenced_table"]) row[@"referenced_table"] = [row[@"referenced_table"] stringByAppendingString:@" \"Table\""];
      [rows addObject:row];
    }
    metadata[collection] = rows;
  }
  [self assertGeneratedArtifactsCompile:metadata];
}

- (void)testGeneratedArtifactsCompileSyntaxOnly {
  [self assertGeneratedArtifactsCompile:[self fixtureMetadata]];
}

- (void)assertGeneratedArtifactsCompile:(NSDictionary *)metadata {
  NSError *error = nil;
  NSDictionary *artifacts = [ALNORMCodegen renderArtifactsFromSchemaMetadata:metadata
                                                                 classPrefix:@"ALNORMX"
                                                                       error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(artifacts);

  NSString *tmpDir = ALNTestTemporaryDirectory(@"orm_codegen");
  XCTAssertNotNil(tmpDir);
  if (tmpDir == nil) {
    return;
  }

  NSString *baseName = [artifacts[@"baseName"] isKindOfClass:[NSString class]] ? artifacts[@"baseName"] : @"ALNORMXGeneratedModels";
  NSString *headerPath = [tmpDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.h", baseName]];
  NSString *implementationPath = [tmpDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.m", baseName]];
  XCTAssertTrue(ALNTestWriteUTF8File(headerPath, artifacts[@"header"], &error), @"%@", error);
  XCTAssertNil(error);
  XCTAssertTrue(ALNTestWriteUTF8File(implementationPath, artifacts[@"implementation"], &error), @"%@", error);
  XCTAssertNil(error);

  NSString *repoRoot = ALNTestRepoRoot();
  NSString *includeFlags = [self syntaxOnlyIncludeFlagsWithRepoRoot:repoRoot temporaryDir:tmpDir];
#if defined(__APPLE__)
  NSString *command = [NSString stringWithFormat:
      @"set -euo pipefail && "
       "cd %@ && "
       "xcrun clang -isysroot \"$(xcrun --show-sdk-path)\" -arch arm64 -fobjc-arc -fsyntax-only "
       "%@ %@",
      ALNTestShellQuote(repoRoot),
      includeFlags,
      ALNTestShellQuote(implementationPath)];
#else
  NSString *command = [NSString stringWithFormat:
      @"set -euo pipefail && "
       "cd %@ && "
       "%@ && "
       "LD_PRELOAD='' XCTEST_LD_PRELOAD='' ASAN_OPTIONS='' UBSAN_OPTIONS='' EXTRA_OBJC_FLAGS='' "
       "clang $(gnustep-config --objc-flags) %@ -Werror=incompatible-property-type -Werror=property-attribute-mismatch -Werror=nullability -fsyntax-only "
       "%@ $(find modules -mindepth 2 -maxdepth 2 -type d -name Sources -printf ' -I%%p') %@",
      ALNTestShellQuote(repoRoot),
      ALNTestGNUstepSourceCommandForRepoRoot(repoRoot),
      [self gnuStepSyntaxOnlyContractFlags],
      includeFlags,
      ALNTestShellQuote(implementationPath)];
#endif
  int exitCode = 0;
  NSString *output = ALNTestRunShellCapture(command, &exitCode);
  XCTAssertEqual(0, exitCode, @"%@", output);
}

- (void)testStandaloneUmbrellasCompileWithoutFrameworkUmbrella {
  NSString *tmpDir = ALNTestTemporaryDirectory(@"orm_umbrella_compile");
  XCTAssertNotNil(tmpDir);
  if (tmpDir == nil) {
    return;
  }

  NSString *repoRoot = ALNTestRepoRoot();
  NSError *error = nil;

  NSString *ormSourcePath = [tmpDir stringByAppendingPathComponent:@"orm_only.m"];
  NSString *ormSource = @"#import <Foundation/Foundation.h>\n"
                        "#import \"ArlenData/ArlenData.h\"\n"
                        "#import \"ArlenORM/ArlenORM.h\"\n"
                        "int main(void) {\n"
                        "  ALNSQLBuilder *builder = [ALNSQLBuilder selectFrom:@\"users\" columns:@[@\"id\"]];\n"
                        "  (void)builder;\n"
                        "  ALNORMContext *context = nil;\n"
                        "  (void)context;\n"
                        "  return 0;\n"
                        "}\n";
  XCTAssertTrue(ALNTestWriteUTF8File(ormSourcePath, ormSource, &error), @"%@", error);
  XCTAssertNil(error);

  NSString *frameworkSourcePath = [tmpDir stringByAppendingPathComponent:@"framework_only.m"];
  NSString *frameworkSource = @"#import <Foundation/Foundation.h>\n"
                              "#import \"Arlen/Arlen.h\"\n"
                              "int main(void) {\n"
                              "  ALNApplication *app = nil;\n"
                              "  (void)app;\n"
                              "  return 0;\n"
                              "}\n";
  XCTAssertTrue(ALNTestWriteUTF8File(frameworkSourcePath, frameworkSource, &error), @"%@", error);
  XCTAssertNil(error);

  NSArray<NSString *> *sourcePaths = @[ ormSourcePath, frameworkSourcePath ];
  NSString *includeFlags = [self syntaxOnlyIncludeFlagsWithRepoRoot:repoRoot temporaryDir:tmpDir];
  for (NSString *sourcePath in sourcePaths) {
#if defined(__APPLE__)
    NSString *command = [NSString stringWithFormat:
        @"set -euo pipefail && "
         "cd %@ && "
         "xcrun clang -isysroot \"$(xcrun --show-sdk-path)\" -arch arm64 -fobjc-arc -fsyntax-only "
         "%@ %@",
        ALNTestShellQuote(repoRoot),
        includeFlags,
        ALNTestShellQuote(sourcePath)];
#else
    NSString *command = [NSString stringWithFormat:
        @"set -euo pipefail && "
         "cd %@ && "
         "%@ && "
         "LD_PRELOAD='' XCTEST_LD_PRELOAD='' ASAN_OPTIONS='' UBSAN_OPTIONS='' EXTRA_OBJC_FLAGS='' "
         "clang $(gnustep-config --objc-flags) %@ -Werror=incompatible-property-type -Werror=property-attribute-mismatch -Werror=nullability -fsyntax-only "
         "%@ $(find modules -mindepth 2 -maxdepth 2 -type d -name Sources -printf ' -I%%p') %@",
        ALNTestShellQuote(repoRoot),
        ALNTestGNUstepSourceCommandForRepoRoot(repoRoot),
        [self gnuStepSyntaxOnlyContractFlags],
        includeFlags,
        ALNTestShellQuote(sourcePath)];
#endif
    int exitCode = 0;
    NSString *output = ALNTestRunShellCapture(command, &exitCode);
    XCTAssertEqual(0, exitCode, @"%@", output);
  }
}

@end
