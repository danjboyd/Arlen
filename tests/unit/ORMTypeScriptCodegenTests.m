#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "../shared/ALNTestSupport.h"
#import "ArlenORM/ArlenORM.h"

@interface ORMTypeScriptCodegenTests : XCTestCase
@end

@implementation ORMTypeScriptCodegenTests

- (NSDictionary *)ormFixture {
  NSError *error = nil;
  NSDictionary *fixture =
      ALNTestJSONDictionaryAtRelativePath(@"tests/fixtures/phase26/orm_schema_metadata_contract.json", &error);
  XCTAssertNil(error);
  XCTAssertNotNil(fixture);
  return fixture ?: @{};
}

- (NSDictionary *)fixtureMetadata {
  NSDictionary *fixture = [self ormFixture];
  return [fixture[@"metadata"] isKindOfClass:[NSDictionary class]] ? fixture[@"metadata"] : @{};
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

- (NSDictionary *)openAPIFixture {
  NSError *error = nil;
  NSDictionary *fixture =
      ALNTestJSONDictionaryAtRelativePath(@"tests/fixtures/phase28/openapi_contract.json", &error);
  XCTAssertNil(error);
  XCTAssertNotNil(fixture);
  return fixture ?: @{};
}

- (NSDictionary *)reversedOpenAPIFixture {
  NSDictionary *fixture = [self openAPIFixture];
  NSDictionary *paths = [fixture[@"paths"] isKindOfClass:[NSDictionary class]] ? fixture[@"paths"] : @{};
  NSMutableDictionary *reversedPaths = [NSMutableDictionary dictionary];
  NSArray *pathKeys = [[[paths allKeys] reverseObjectEnumerator] allObjects];
  for (NSString *path in pathKeys) {
    NSDictionary *pathItem = [paths[path] isKindOfClass:[NSDictionary class]] ? paths[path] : @{};
    NSMutableDictionary *reversedPathItem = [NSMutableDictionary dictionary];
    NSArray *methods = [[[pathItem allKeys] reverseObjectEnumerator] allObjects];
    for (NSString *method in methods) {
      reversedPathItem[method] = pathItem[method];
    }
    reversedPaths[path] = reversedPathItem;
  }
  NSMutableDictionary *reversed = [fixture mutableCopy];
  reversed[@"paths"] = reversedPaths;
  return reversed;
}

- (NSDictionary *)renderArtifactsWithMetadata:(NSDictionary *)metadata
                                      openAPI:(NSDictionary *)openAPI
                                        error:(NSError **)error {
  return [ALNORMTypeScriptCodegen renderArtifactsFromSchemaMetadata:metadata
                                                        classPrefix:@"ALNORMX"
                                                     databaseTarget:nil
                                                 descriptorOverrides:nil
                                                openAPISpecification:openAPI
                                                        packageName:@"arlen-phase28-client"
                                                            targets:@[ @"all" ]
                                                              error:error];
}

- (void)testRenderArtifactsAreDeterministicAcrossMetadataAndOpenAPIOrdering {
  NSError *firstError = nil;
  NSDictionary *first = [self renderArtifactsWithMetadata:[self fixtureMetadata]
                                                  openAPI:[self openAPIFixture]
                                                    error:&firstError];
  XCTAssertNil(firstError);
  XCTAssertNotNil(first);

  NSError *secondError = nil;
  NSDictionary *second = [self renderArtifactsWithMetadata:[self reversedMetadata]
                                                   openAPI:[self reversedOpenAPIFixture]
                                                     error:&secondError];
  XCTAssertNil(secondError);
  XCTAssertNotNil(second);

  XCTAssertEqualObjects(first[@"manifest"], second[@"manifest"]);

  NSDictionary *firstFiles = [first[@"files"] isKindOfClass:[NSDictionary class]] ? first[@"files"] : @{};
  NSDictionary *secondFiles = [second[@"files"] isKindOfClass:[NSDictionary class]] ? second[@"files"] : @{};
  XCTAssertEqualObjects(firstFiles[@"src/models.ts"], secondFiles[@"src/models.ts"]);
  XCTAssertEqualObjects(firstFiles[@"src/validators.ts"], secondFiles[@"src/validators.ts"]);
  XCTAssertEqualObjects(firstFiles[@"src/query.ts"], secondFiles[@"src/query.ts"]);
  XCTAssertEqualObjects(firstFiles[@"src/client.ts"], secondFiles[@"src/client.ts"]);
  XCTAssertEqualObjects(firstFiles[@"src/react.ts"], secondFiles[@"src/react.ts"]);
  XCTAssertEqualObjects(firstFiles[@"src/meta.ts"], secondFiles[@"src/meta.ts"]);
  XCTAssertEqualObjects(first[@"modelCount"], @6);
  XCTAssertEqualObjects(first[@"operationCount"], @7);
  XCTAssertEqualObjects(first[@"resourceCount"], @1);
  XCTAssertEqualObjects(first[@"moduleCount"], @4);

  NSString *models = [firstFiles[@"src/models.ts"] isKindOfClass:[NSString class]] ? firstFiles[@"src/models.ts"] : @"";
  NSString *validators =
      [firstFiles[@"src/validators.ts"] isKindOfClass:[NSString class]] ? firstFiles[@"src/validators.ts"] : @"";
  NSString *query = [firstFiles[@"src/query.ts"] isKindOfClass:[NSString class]] ? firstFiles[@"src/query.ts"] : @"";
  NSString *client = [firstFiles[@"src/client.ts"] isKindOfClass:[NSString class]] ? firstFiles[@"src/client.ts"] : @"";
  NSString *react = [firstFiles[@"src/react.ts"] isKindOfClass:[NSString class]] ? firstFiles[@"src/react.ts"] : @"";
  NSString *meta = [firstFiles[@"src/meta.ts"] isKindOfClass:[NSString class]] ? firstFiles[@"src/meta.ts"] : @"";
  NSString *packageJSON =
      [firstFiles[@"package.json"] isKindOfClass:[NSString class]] ? firstFiles[@"package.json"] : @"";

  XCTAssertTrue([models containsString:@"export interface PublicUser {"]);
  XCTAssertTrue([models containsString:@"readonly id: string;"]);
  XCTAssertTrue([models containsString:@"readonly posts?: PublicPost[];"]);
  XCTAssertTrue([models containsString:@"export interface PublicUserCreateInput {"]);
  XCTAssertTrue([models containsString:@"export type PublicUserEmailCreateInput = never;"]);
  XCTAssertTrue([models containsString:@"export type PublicUserUniqueWhere = {"]);
  XCTAssertTrue([models containsString:@"email: string;"]);

  XCTAssertTrue([validators containsString:@"export const publicUserCreateInputSchema"]);
  XCTAssertTrue([validators containsString:@"export const createUserRequestSchema"]);
  XCTAssertTrue([validators containsString:@"validatePublicUserCreateInput"]);
  XCTAssertTrue([validators containsString:@"literalValues"]);
  XCTAssertTrue([validators containsString:@"ArlenFormFieldAdapter"]);
  XCTAssertTrue([validators containsString:@"\"required\": true"]);
  XCTAssertFalse([validators containsString:@"\"required\": 1"]);

  XCTAssertTrue([query containsString:@"export const usersResourceQueryContract"]);
  XCTAssertTrue([query containsString:@"buildUsersQueryParams"]);
  XCTAssertTrue([query containsString:@"export type PublicUserResourceIncludeField = 'posts' | 'profile';"]);
  XCTAssertTrue([query containsString:@"export const publicUserRelationContracts"]);

  XCTAssertTrue([client containsString:@"export class ArlenClient"]);
  XCTAssertTrue([client containsString:@"async listUsers"]);
  XCTAssertTrue([client containsString:@"async getUser"]);
  XCTAssertTrue([client containsString:@"async getSession"]);
  XCTAssertTrue([client containsString:@"export const arlenOperations = {"]);
  XCTAssertTrue([client containsString:@"baseUrl"]);

  XCTAssertTrue([react containsString:@"useListUsersQuery"]);
  XCTAssertTrue([react containsString:@"useCreateUserMutation"]);
  XCTAssertTrue([react containsString:@"invalidateAfterCreateUser"]);
  XCTAssertTrue([react containsString:@"export const arlenInvalidationHints = {"]);

  XCTAssertTrue([meta containsString:@"export const arlenWorkspaceHints"]);
  XCTAssertTrue([meta containsString:@"export const arlenResourceRegistry"]);
  XCTAssertTrue([meta containsString:@"export const arlenModuleRegistry"]);
  XCTAssertTrue([meta containsString:@"admin-ui"]);
  XCTAssertTrue([meta containsString:@"search_capabilities"]);

  NSError *packageError = nil;
  NSDictionary *packageObject = ALNTestJSONDictionaryFromString(packageJSON, &packageError);
  XCTAssertNil(packageError);
  XCTAssertEqualObjects(@"arlen-phase28-client", packageObject[@"name"]);
  XCTAssertEqualObjects(@"./src/index.ts", packageObject[@"types"]);
  XCTAssertEqualObjects(@"tsc --noEmit", packageObject[@"scripts"][@"typecheck"]);
  XCTAssertEqualObjects(@"^5.0.0", packageObject[@"devDependencies"][@"typescript"]);
  XCTAssertEqualObjects(@"./src/validators.ts", packageObject[@"exports"][@"./validators"]);
  XCTAssertEqualObjects(@"./src/query.ts", packageObject[@"exports"][@"./query"]);
  XCTAssertEqualObjects(@"./src/meta.ts", packageObject[@"exports"][@"./meta"]);

  NSError *manifestError = nil;
  NSDictionary *manifest = ALNTestJSONDictionaryFromString(first[@"manifest"], &manifestError);
  XCTAssertNil(manifestError);
  XCTAssertEqualObjects(@"arlen-typescript-contract-v1", manifest[@"format"]);
  XCTAssertEqualObjects(@7, manifest[@"operation_count"]);
  XCTAssertEqualObjects(@6, manifest[@"model_count"]);
  XCTAssertEqualObjects(@1, manifest[@"resource_count"]);
  XCTAssertEqualObjects(@4, manifest[@"module_count"]);
}

- (void)testORMManifestInputMatchesSchemaMetadataInput {
  NSError *ormError = nil;
  NSDictionary *ormArtifacts = [ALNORMCodegen renderArtifactsFromSchemaMetadata:[self fixtureMetadata]
                                                                    classPrefix:@"ALNORMX"
                                                                          error:&ormError];
  XCTAssertNil(ormError);
  XCTAssertNotNil(ormArtifacts);

  NSError *manifestError = nil;
  NSDictionary *ormManifest = ALNTestJSONDictionaryFromString(ormArtifacts[@"manifest"], &manifestError);
  XCTAssertNil(manifestError);
  XCTAssertNotNil(ormManifest);

  NSError *fromMetadataError = nil;
  NSDictionary *fromMetadata = [self renderArtifactsWithMetadata:[self fixtureMetadata]
                                                         openAPI:[self openAPIFixture]
                                                           error:&fromMetadataError];
  XCTAssertNil(fromMetadataError);
  XCTAssertNotNil(fromMetadata);

  NSError *fromManifestError = nil;
  NSDictionary *fromManifest = [ALNORMTypeScriptCodegen renderArtifactsFromORMManifest:ormManifest
                                                                   openAPISpecification:[self openAPIFixture]
                                                                           packageName:@"arlen-phase28-client"
                                                                               targets:@[ @"all" ]
                                                                                 error:&fromManifestError];
  XCTAssertNil(fromManifestError);
  XCTAssertNotNil(fromManifest);

  NSDictionary *fromMetadataFiles =
      [fromMetadata[@"files"] isKindOfClass:[NSDictionary class]] ? fromMetadata[@"files"] : @{};
  NSDictionary *fromManifestFiles =
      [fromManifest[@"files"] isKindOfClass:[NSDictionary class]] ? fromManifest[@"files"] : @{};
  XCTAssertEqualObjects(fromMetadataFiles[@"src/models.ts"], fromManifestFiles[@"src/models.ts"]);
  XCTAssertEqualObjects(fromMetadataFiles[@"src/validators.ts"], fromManifestFiles[@"src/validators.ts"]);
  XCTAssertEqualObjects(fromMetadataFiles[@"src/query.ts"], fromManifestFiles[@"src/query.ts"]);
  XCTAssertEqualObjects(fromMetadataFiles[@"src/client.ts"], fromManifestFiles[@"src/client.ts"]);
  XCTAssertEqualObjects(fromMetadataFiles[@"src/react.ts"], fromManifestFiles[@"src/react.ts"]);
  XCTAssertEqualObjects(fromMetadataFiles[@"src/meta.ts"], fromManifestFiles[@"src/meta.ts"]);
  XCTAssertEqualObjects(fromMetadata[@"manifest"], fromManifest[@"manifest"]);
}

- (void)testClientTargetsRequireOpenAPISpecification {
  NSError *error = nil;
  NSDictionary *artifacts =
      [ALNORMTypeScriptCodegen renderArtifactsFromSchemaMetadata:[self fixtureMetadata]
                                                     classPrefix:@"ALNORMX"
                                                  databaseTarget:nil
                                              descriptorOverrides:nil
                                             openAPISpecification:nil
                                                     packageName:@"arlen-phase28-client"
                                                         targets:@[ @"client" ]
                                                           error:&error];
  XCTAssertNil(artifacts);
  XCTAssertNotNil(error);
  XCTAssertTrue([[error localizedDescription] containsString:@"OpenAPI"]);
}

- (void)testDuplicateOperationIDsFailClosed {
  NSDictionary *openAPI = @{
    @"openapi" : @"3.1.0",
    @"info" : @{
      @"title" : @"Duplicate operation fixture",
      @"version" : @"0.1.0",
    },
    @"paths" : @{
      @"/api/users" : @{
        @"get" : @{
          @"operationId" : @"user_lookup",
          @"responses" : @{
            @"200" : @{
              @"description" : @"ok",
            },
          },
        },
      },
      @"/api/users/{id}" : @{
        @"get" : @{
          @"operationId" : @"user_lookup",
          @"parameters" : @[
            @{
              @"name" : @"id",
              @"in" : @"path",
              @"required" : @YES,
              @"schema" : @{
                @"type" : @"string",
              },
            },
          ],
          @"responses" : @{
            @"200" : @{
              @"description" : @"ok",
            },
          },
        },
      },
    },
  };

  NSError *error = nil;
  NSDictionary *artifacts =
      [ALNORMTypeScriptCodegen renderArtifactsFromSchemaMetadata:[self fixtureMetadata]
                                                     classPrefix:@"ALNORMX"
                                                  databaseTarget:nil
                                              descriptorOverrides:nil
                                             openAPISpecification:openAPI
                                                     packageName:@"arlen-phase28-client"
                                                         targets:@[ @"client" ]
                                                           error:&error];
  XCTAssertNil(artifacts);
  XCTAssertNotNil(error);
  XCTAssertTrue([[error localizedDescription] containsString:@"collides"]);
}

- (void)testValidatorsAndQueryTargetsDoNotRequireOpenAPI {
  NSError *error = nil;
  NSDictionary *artifacts =
      [ALNORMTypeScriptCodegen renderArtifactsFromSchemaMetadata:[self fixtureMetadata]
                                                     classPrefix:@"ALNORMX"
                                                  databaseTarget:nil
                                              descriptorOverrides:nil
                                             openAPISpecification:nil
                                                     packageName:@"arlen-phase28-client"
                                                         targets:@[ @"validators", @"query" ]
                                                           error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(artifacts);
  NSDictionary *files = [artifacts[@"files"] isKindOfClass:[NSDictionary class]] ? artifacts[@"files"] : @{};
  XCTAssertNotNil(files[@"src/models.ts"]);
  XCTAssertNotNil(files[@"src/validators.ts"]);
  XCTAssertNotNil(files[@"src/query.ts"]);
  XCTAssertNil(files[@"src/client.ts"]);
  XCTAssertNil(files[@"src/meta.ts"]);
}

- (void)testResourceQueryMetadataFailsClosedOnUnknownRelation {
  NSMutableDictionary *openAPI = [[self openAPIFixture] mutableCopy];
  NSMutableDictionary *extension = [openAPI[@"x-arlen"] mutableCopy];
  NSMutableArray *resources = [extension[@"resources"] mutableCopy];
  NSMutableDictionary *usersResource = [resources[0] mutableCopy];
  NSMutableDictionary *query = [usersResource[@"query"] mutableCopy];
  query[@"allowed_include"] = @[ @"profile", @"posts", @"notARelation" ];
  usersResource[@"query"] = query;
  resources[0] = usersResource;
  extension[@"resources"] = resources;
  openAPI[@"x-arlen"] = extension;

  NSError *error = nil;
  NSDictionary *artifacts =
      [ALNORMTypeScriptCodegen renderArtifactsFromSchemaMetadata:[self fixtureMetadata]
                                                     classPrefix:@"ALNORMX"
                                                  databaseTarget:nil
                                              descriptorOverrides:nil
                                             openAPISpecification:openAPI
                                                     packageName:@"arlen-phase28-client"
                                                         targets:@[ @"query" ]
                                                           error:&error];
  XCTAssertNil(artifacts);
  XCTAssertNotNil(error);
  XCTAssertTrue([[error localizedDescription] containsString:@"allowed_include"]);
}

- (void)testTypeScriptCodegenCLIFromFixtures {
  NSString *tempDir = ALNTestTemporaryDirectory(@"orm_typescript_codegen");
  XCTAssertNotNil(tempDir);
  if (tempDir == nil) {
    return;
  }

  NSString *ormFixturePath =
      ALNTestPathFromRepoRoot(@"tests/fixtures/phase26/orm_schema_metadata_contract.json");
  NSString *openAPIPath = ALNTestPathFromRepoRoot(@"tests/fixtures/phase28/openapi_contract.json");
  NSString *outputDir = [tempDir stringByAppendingPathComponent:@"frontend/generated/arlen"];
  NSString *manifestPath = [tempDir stringByAppendingPathComponent:@"db/schema/arlen_typescript.json"];

  NSString *arlenCLIPath = ALNTestPathFromRepoRoot(@"bin/arlen");

  NSString *command =
      [NSString stringWithFormat:@"%@ && %@ typescript-codegen --orm-input %@ --openapi-input %@ --output-dir %@ --manifest %@ --package-name %@ --prefix ALNORMX --target all --force",
                                 ALNTestGNUstepSourceCommandForRepoRoot(ALNTestRepoRoot()),
                                 ALNTestShellQuote([arlenCLIPath stringByStandardizingPath]),
                                 ALNTestShellQuote(ormFixturePath),
                                 ALNTestShellQuote(openAPIPath),
                                 ALNTestShellQuote(outputDir),
                                 ALNTestShellQuote(manifestPath),
                                 ALNTestShellQuote(@"arlen-cli-client")];
  int exitCode = 0;
  NSString *output = ALNTestRunShellCapture(command, &exitCode);
  XCTAssertEqual(0, exitCode, @"%@", output);
  XCTAssertTrue([output containsString:@"Generated TypeScript artifacts."]);

  NSString *modelsPath = [outputDir stringByAppendingPathComponent:@"src/models.ts"];
  NSString *validatorsPath = [outputDir stringByAppendingPathComponent:@"src/validators.ts"];
  NSString *queryPath = [outputDir stringByAppendingPathComponent:@"src/query.ts"];
  NSString *clientPath = [outputDir stringByAppendingPathComponent:@"src/client.ts"];
  NSString *reactPath = [outputDir stringByAppendingPathComponent:@"src/react.ts"];
  NSString *metaPath = [outputDir stringByAppendingPathComponent:@"src/meta.ts"];
  NSString *packagePath = [outputDir stringByAppendingPathComponent:@"package.json"];

  XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:modelsPath]);
  XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:validatorsPath]);
  XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:queryPath]);
  XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:clientPath]);
  XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:reactPath]);
  XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:metaPath]);
  XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:packagePath]);
  XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:manifestPath]);

  NSString *models = [NSString stringWithContentsOfFile:modelsPath
                                               encoding:NSUTF8StringEncoding
                                                  error:NULL];
  XCTAssertTrue([models containsString:@"export interface PublicUser"]);
}

@end
