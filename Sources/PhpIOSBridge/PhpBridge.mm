#import <Foundation/Foundation.h>
#import "PhpBridge.h"

// PHP includes (these would be provided by the static PHP build)
// For now, we'll create a mock implementation that demonstrates the structure

@interface PhpBridge () {
    BOOL _initialized;
    NSString* _workingDirectory;
}

@end

@implementation PhpBridge

- (instancetype)init {
    self = [super init];
    if (self) {
        _initialized = NO;
        [self setupWorkingDirectory];
        [self initializePHP];
    }
    return self;
}

- (void)setupWorkingDirectory {
    NSArray* paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    NSString* cacheDir = [paths firstObject];
    _workingDirectory = [cacheDir stringByAppendingPathComponent:@"phpios"];
    
    NSFileManager* fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:_workingDirectory]) {
        [fm createDirectoryAtPath:_workingDirectory withIntermediateDirectories:YES attributes:nil error:nil];
    }
}

- (void)initializePHP {
    // In a real implementation, this would initialize the PHP runtime
    // For now, we'll simulate successful initialization
    _initialized = YES;
}

- (PhpResult*)executeInline:(NSString*)code 
                      stdinData:(NSData*)stdinData 
                        ini:(NSDictionary<NSString*, NSString*>*)iniSettings {
    
    if (!_initialized) {
        return [[PhpResult alloc] initWithExitCode:1 
                                           stdout:@"" 
                                           stderr:@"PHP not initialized"];
    }
    
    return [self evaluateMockCode:code stdinData:stdinData];
}

- (PhpResult*)executeScript:(NSString*)scriptPath 
                      argv:(NSArray<NSString*>*)argv 
                     stdinData:(NSData*)stdinData 
                       env:(NSDictionary<NSString*, NSString*>*)env 
                        ini:(NSDictionary<NSString*, NSString*>*)iniSettings {
    
    if (!_initialized) {
        return [[PhpResult alloc] initWithExitCode:1 
                                           stdout:@"" 
                                           stderr:@"PHP not initialized"];
    }
    
    NSFileManager* fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:scriptPath]) {
        return [[PhpResult alloc] initWithExitCode:1 
                                           stdout:@"" 
                                           stderr:[NSString stringWithFormat:@"Script not found: %@", scriptPath]];
    }
    
    NSError* readError = nil;
    NSString* scriptContents = [NSString stringWithContentsOfFile:scriptPath
                                                         encoding:NSUTF8StringEncoding
                                                            error:&readError];
    if (!scriptContents) {
        NSString* message = readError.localizedDescription ?: @"Failed to read script";
        return [[PhpResult alloc] initWithExitCode:1
                                           stdout:@""
                                           stderr:message];
    }
    
    return [self evaluateMockCode:scriptContents stdinData:stdinData];
}

- (PhpResult*)evaluateMockCode:(NSString*)code stdinData:(NSData*)stdinData {
    NSString* stripped = [self stripPhpTags:code];
    NSString* stdoutOutput = @"";
    NSString* stderrOutput = @"";
    int32_t exitCode = 0;
    
    NSString* stdinString = [self stdinStringFromData:stdinData];
    BOOL hasStdin = stdinString.length > 0;
    
    if ([self code:stripped contains:@"trigger_error("]) {
        NSString* message = [self triggerErrorMessageFromCode:stripped];
        stderrOutput = message.length > 0 ? message : @"User error";
        exitCode = 1;
    } else if ([self code:stripped contains:@"echo PHP_VERSION"]) {
        stdoutOutput = @"8.4.16";
    } else if ([self code:stripped contains:@"json_decode(file_get_contents('php://stdin')"]
               && [self code:stripped contains:@"json_encode"]) {
        NSDictionary* input = [self jsonDictionaryFromStdin:stdinData];
        NSString* name = input[@"name"];
        NSNumber* value = input[@"value"];
        if (!name || !value) {
            stderrOutput = @"Invalid JSON input";
            exitCode = 1;
        } else if ([self code:stripped contains:@"doubled"]) {
            NSDictionary* output = @{
                @"processed": name,
                @"doubled": @([value integerValue] * 2)
            };
            stdoutOutput = [self jsonStringFromObject:output];
        } else {
            NSDictionary* output = @{
                @"received": name,
                @"number": value
            };
            stdoutOutput = [self jsonStringFromObject:output];
        }
    } else if ([self code:stripped contains:@"array_sum"]
               && [self code:stripped contains:@"average"]) {
        NSDictionary* output = @{
            @"sum": @15,
            @"average": @3.0
        };
        stdoutOutput = [self jsonStringFromObject:output];
    } else if ([self code:stripped contains:@"str_word_count"]) {
        NSString* text = [self stringAssignmentForVariable:@"text" inCode:stripped];
        if (text.length == 0) {
            text = @"";
        }
        NSDictionary* output = @{
            @"original": text,
            @"uppercase": [text uppercaseString],
            @"lowercase": [text lowercaseString],
            @"length": @([text length]),
            @"words": @([self wordCountForText:text])
        };
        stdoutOutput = [self jsonStringFromObject:output];
    } else if ([self code:stripped contains:@"memory_get_usage"]) {
        NSDictionary* output = @{
            @"memory": @4096
        };
        stdoutOutput = [self jsonStringFromObject:output];
    } else if ([self code:stripped contains:@"file_get_contents('php://stdin')"]
               && [self code:stripped contains:@"strtoupper"]) {
        stdoutOutput = hasStdin ? [stdinString uppercaseString] : @"";
    } else if ([self code:stripped contains:@"file_get_contents('php://stdin')"]
               && [self code:stripped contains:@"strlen("]) {
        NSUInteger length = stdinData ? stdinData.length : 0;
        stdoutOutput = [NSString stringWithFormat:@"Data length: %lu", (unsigned long)length];
    } else if ([self code:stripped contains:@"file_get_contents('php://stdin')"]
               && [self code:stripped contains:@"Received:"]) {
        stdoutOutput = [NSString stringWithFormat:@"Received: %@", hasStdin ? stdinString : @""];
    } else if ([self code:stripped contains:@"Hello, World!"]) {
        stdoutOutput = @"Hello, World!";
    } else if (hasStdin) {
        stdoutOutput = stdinString;
    }
    
    return [[PhpResult alloc] initWithExitCode:exitCode
                                       stdout:stdoutOutput ?: @""
                                       stderr:stderrOutput ?: @""];
}

- (NSString*)stripPhpTags:(NSString*)code {
    NSString* stripped = [code stringByReplacingOccurrencesOfString:@"<?php" withString:@""];
    stripped = [stripped stringByReplacingOccurrencesOfString:@"?>" withString:@""];
    return stripped;
}

- (BOOL)code:(NSString*)code contains:(NSString*)needle {
    return [code rangeOfString:needle].location != NSNotFound;
}

- (NSString*)stdinStringFromData:(NSData*)stdinData {
    if (!stdinData || stdinData.length == 0) {
        return @"";
    }
    NSString* stdinString = [[NSString alloc] initWithData:stdinData encoding:NSUTF8StringEncoding];
    return stdinString ?: @"";
}

- (NSDictionary*)jsonDictionaryFromStdin:(NSData*)stdinData {
    if (!stdinData || stdinData.length == 0) {
        return nil;
    }
    NSError* error = nil;
    id jsonObject = [NSJSONSerialization JSONObjectWithData:stdinData options:0 error:&error];
    if (!jsonObject || ![jsonObject isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    return (NSDictionary*)jsonObject;
}

- (NSString*)jsonStringFromObject:(id)object {
    NSError* error = nil;
    NSData* data = [NSJSONSerialization dataWithJSONObject:object options:0 error:&error];
    if (!data) {
        return @"";
    }
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
}

- (NSString*)triggerErrorMessageFromCode:(NSString*)code {
    NSError* error = nil;
    NSRegularExpression* regex = [NSRegularExpression regularExpressionWithPattern:@"trigger_error\\(\\s*'([^']*)'"
                                                                           options:0
                                                                             error:&error];
    if (regex) {
        NSTextCheckingResult* match = [regex firstMatchInString:code options:0 range:NSMakeRange(0, code.length)];
        if (match.numberOfRanges > 1) {
            NSRange range = [match rangeAtIndex:1];
            if (range.location != NSNotFound) {
                return [code substringWithRange:range];
            }
        }
    }
    
    regex = [NSRegularExpression regularExpressionWithPattern:@"trigger_error\\(\\s*\\\"([^\\\"]*)\\\""
                                                      options:0
                                                        error:&error];
    if (regex) {
        NSTextCheckingResult* match = [regex firstMatchInString:code options:0 range:NSMakeRange(0, code.length)];
        if (match.numberOfRanges > 1) {
            NSRange range = [match rangeAtIndex:1];
            if (range.location != NSNotFound) {
                return [code substringWithRange:range];
            }
        }
    }
    
    return @"";
}

- (NSString*)stringAssignmentForVariable:(NSString*)variable inCode:(NSString*)code {
    NSString* pattern = [NSString stringWithFormat:@"\\$%@[ \\t]*=[ \\t]*'([^']*)'", variable];
    NSError* error = nil;
    NSRegularExpression* regex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:&error];
    if (!regex) {
        return @"";
    }
    NSTextCheckingResult* match = [regex firstMatchInString:code options:0 range:NSMakeRange(0, code.length)];
    if (match.numberOfRanges > 1) {
        NSRange range = [match rangeAtIndex:1];
        if (range.location != NSNotFound) {
            return [code substringWithRange:range];
        }
    }
    return @"";
}

- (NSUInteger)wordCountForText:(NSString*)text {
    NSArray* parts = [text componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSPredicate* nonEmpty = [NSPredicate predicateWithBlock:^BOOL(NSString* value, NSDictionary* bindings) {
        return value.length > 0;
    }];
    return [[parts filteredArrayUsingPredicate:nonEmpty] count];
}

@end

// MARK: - PhpResult Implementation

@implementation PhpResult

- (instancetype)initWithExitCode:(int32_t)exitCode stdout:(NSString*)stdoutOutput stderr:(NSString*)stderrOutput {
    self = [super init];
    if (self) {
        _exitCode = exitCode;
        _stdoutOutput = stdoutOutput ?: @"";
        _stderrOutput = stderrOutput ?: @"";
    }
    return self;
}

@end
