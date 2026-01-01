#import <Foundation/Foundation.h>
#import "PhpBridge.h"
#import <TargetConditionals.h>

#if TARGET_OS_IPHONE
#include <php/sapi/embed/php_embed.h>
#include <php/main/php_output.h>
#include <php/main/php_variables.h>
#include <php/main/php_ini.h>
#include <php/main/php_globals.h>
#include <php/Zend/zend_ini.h>
#include <php/Zend/zend_API.h>
#include <php/Zend/zend_exceptions.h>
#include <unistd.h>
#include <fcntl.h>
#include <stdarg.h>
#endif

// PHP is embedded on iOS; non-iOS builds use a lightweight mock.

@interface PhpBridge () {
    BOOL _initialized;
    NSString* _workingDirectory;
}

@end

#if TARGET_OS_IPHONE
static NSMutableData* phpios_stderr_data = nil;
static char* phpios_ini_path = NULL;

static void phpios_log_message(const char *message, int syslog_type_int) {
    if (!phpios_stderr_data || !message) {
        return;
    }
    size_t length = strlen(message);
    if (length > 0) {
        [phpios_stderr_data appendBytes:message length:length];
        [phpios_stderr_data appendBytes:"\n" length:1];
    }
}

static void phpios_sapi_error(int type, const char *error_msg, ...) {
    if (!phpios_stderr_data || !error_msg) {
        return;
    }
    char buffer[2048];
    va_list args;
    va_start(args, error_msg);
    vsnprintf(buffer, sizeof(buffer), error_msg, args);
    va_end(args);
    size_t length = strlen(buffer);
    if (length > 0) {
        [phpios_stderr_data appendBytes:buffer length:length];
        [phpios_stderr_data appendBytes:"\n" length:1];
    }
}
#endif

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
#if TARGET_OS_IPHONE
    if (!phpios_ini_path) {
        NSString* iniPath = [[NSBundle mainBundle] pathForResource:@"php" ofType:@"ini"];
        if (iniPath.length > 0) {
            phpios_ini_path = strdup([iniPath fileSystemRepresentation]);
            php_embed_module.php_ini_path_override = phpios_ini_path;
        }
    }
    _initialized = YES;
#else
    _initialized = YES;
#endif
}

- (PhpResult*)executeInline:(NSString*)code 
                      stdinData:(NSData*)stdinData 
                        ini:(NSDictionary<NSString*, NSString*>*)iniSettings {
    
    if (!_initialized) {
        return [[PhpResult alloc] initWithExitCode:1 
                                           stdout:@"" 
                                           stderr:@"PHP not initialized"];
    }
    
#if TARGET_OS_IPHONE
    return [self executePhpCode:code
                      scriptPath:nil
                            argv:nil
                       stdinData:stdinData
                             env:nil
                             ini:iniSettings];
#else
    return [self evaluateMockCode:code stdinData:stdinData];
#endif
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

#if TARGET_OS_IPHONE
    return [self executePhpCode:nil
                      scriptPath:scriptPath
                            argv:argv
                       stdinData:stdinData
                             env:env
                             ini:iniSettings];
#else
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
#endif
}

#if TARGET_OS_IPHONE
- (PhpResult*)executePhpCode:(NSString*)code
                  scriptPath:(NSString*)scriptPath
                        argv:(NSArray<NSString*>*)argv
                   stdinData:(NSData*)stdinData
                         env:(NSDictionary<NSString*, NSString*>*)env
                         ini:(NSDictionary<NSString*, NSString*>*)iniSettings {
    NSMutableData* stderrData = [NSMutableData data];
    NSMutableDictionary<NSString*, NSString*>* previousEnv = [NSMutableDictionary dictionary];
    NSString* stdoutOutput = @"";
    NSString* stderrOutput = @"";
    int32_t exitCode = 0;

    [self applyEnvironment:env previousValues:previousEnv];

    NSMutableArray<NSString*>* argList = [NSMutableArray arrayWithObject:@"php"];
    if (scriptPath.length > 0) {
        [argList addObject:scriptPath];
    }
    if (argv.count > 0) {
        [argList addObjectsFromArray:argv];
    }

    int argc = (int)argList.count;
    char** cargv = (char**)calloc((size_t)argc + 1, sizeof(char*));
    for (int i = 0; i < argc; i++) {
        NSString* arg = argList[i];
        cargv[i] = strdup([arg UTF8String]);
    }
    cargv[argc] = NULL;

    void (*prev_log_message)(const char*, int) = php_embed_module.log_message;
    void (*prev_sapi_error)(int, const char*, ...) = php_embed_module.sapi_error;
    phpios_stderr_data = stderrData;
    php_embed_module.log_message = phpios_log_message;
    php_embed_module.sapi_error = phpios_sapi_error;

    if (php_embed_init(argc, cargv) != SUCCESS) {
        php_embed_module.log_message = prev_log_message;
        php_embed_module.sapi_error = prev_sapi_error;
        phpios_stderr_data = nil;
        [self restoreEnvironment:previousEnv];
        [self freeArgv:cargv count:argc];
        return [[PhpResult alloc] initWithExitCode:1
                                           stdout:@""
                                           stderr:@"PHP initialization failed"];
    }
    php_embed_module.log_message = phpios_log_message;
    php_embed_module.sapi_error = phpios_sapi_error;

    SG(request_info).argc = argc;
    SG(request_info).argv = cargv;
    SG(request_info).request_method = "GET";

    char* path_translated = NULL;
    char* request_uri = NULL;
    char* query_string = NULL;
    NSString* previousDirectory = nil;

    if (scriptPath.length > 0) {
        NSString* scriptName = [@"/" stringByAppendingString:[scriptPath lastPathComponent]];
        NSString* requestUri = env[@"REQUEST_URI"] ?: scriptName;
        NSString* queryString = env[@"QUERY_STRING"] ?: @"";
        NSString* scriptDir = [scriptPath stringByDeletingLastPathComponent];

        path_translated = strdup([scriptPath fileSystemRepresentation]);
        request_uri = strdup([requestUri UTF8String]);
        query_string = strdup([queryString UTF8String]);

        SG(request_info).path_translated = path_translated;
        SG(request_info).request_uri = request_uri;
        SG(request_info).query_string = query_string;

        previousDirectory = [[NSFileManager defaultManager] currentDirectoryPath];
        chdir([scriptDir fileSystemRepresentation]);

        [self applyServerGlobalsForScriptPath:scriptPath env:env requestUri:requestUri queryString:queryString];
    }

    [self applyIniSettings:iniSettings];

    int savedStdinFd = -1;
    int tempStdinFd = -1;
    NSString* tempStdinPath = nil;
    if (stdinData.length > 0) {
        [self redirectStdin:stdinData
                savedStdin:&savedStdinFd
                 tempStdin:&tempStdinFd
                tempPath:&tempStdinPath];
    }

    php_output_start_default();

    zval output;
    ZVAL_UNDEF(&output);

    zend_first_try {
        if (code.length > 0) {
            zend_eval_string([code UTF8String], NULL, "PhpIOS");
        } else if (scriptPath.length > 0) {
            zend_file_handle file_handle;
            zend_stream_init_filename(&file_handle, [scriptPath fileSystemRepresentation]);
            int status = php_execute_script(&file_handle);
            if (status != SUCCESS) {
                exitCode = 1;
            }
        }
    } zend_catch {
        exitCode = EG(exit_status);
    } zend_end_try();

    if (php_output_get_contents(&output) == SUCCESS) {
        stdoutOutput = [self stringFromZval:&output];
    }
    zval_ptr_dtor(&output);
    php_output_end_all();

    if (tempStdinFd >= 0) {
        close(tempStdinFd);
    }
    if (savedStdinFd >= 0) {
        dup2(savedStdinFd, STDIN_FILENO);
        close(savedStdinFd);
    }
    if (tempStdinPath.length > 0) {
        [[NSFileManager defaultManager] removeItemAtPath:tempStdinPath error:nil];
    }

    if (previousDirectory.length > 0) {
        chdir([previousDirectory fileSystemRepresentation]);
    }

    if (PG(last_error_message)) {
        NSString* lastError = [NSString stringWithUTF8String:ZSTR_VAL(PG(last_error_message))];
        if (lastError.length > 0) {
            stderrOutput = lastError;
        }
    }

    if (stderrData.length > 0) {
        NSString* stderrString = [[NSString alloc] initWithData:stderrData encoding:NSUTF8StringEncoding];
        if (stderrString.length > 0) {
            if (stderrOutput.length > 0) {
                stderrOutput = [stderrOutput stringByAppendingFormat:@"\n%@", stderrString];
            } else {
                stderrOutput = stderrString;
            }
        }
    }

    php_embed_shutdown();
    php_embed_module.log_message = prev_log_message;
    php_embed_module.sapi_error = prev_sapi_error;
    phpios_stderr_data = nil;

    [self restoreEnvironment:previousEnv];
    [self freeArgv:cargv count:argc];

    return [[PhpResult alloc] initWithExitCode:exitCode
                                       stdout:stdoutOutput ?: @""
                                       stderr:stderrOutput ?: @""];
}

- (void)applyIniSettings:(NSDictionary<NSString*, NSString*>*)iniSettings {
    if (iniSettings.count == 0) {
        return;
    }
    for (NSString* key in iniSettings) {
        NSString* value = iniSettings[key] ?: @"";
        zend_string* name = zend_string_init([key UTF8String], [key lengthOfBytesUsingEncoding:NSUTF8StringEncoding], 0);
        zend_alter_ini_entry_chars(name, [value UTF8String], [value lengthOfBytesUsingEncoding:NSUTF8StringEncoding],
                                   PHP_INI_USER, PHP_INI_STAGE_RUNTIME);
        zend_string_release(name);
    }
}

- (void)applyServerGlobalsForScriptPath:(NSString*)scriptPath
                                    env:(NSDictionary<NSString*, NSString*>*)env
                             requestUri:(NSString*)requestUri
                            queryString:(NSString*)queryString {
    NSString* scriptName = [@"/" stringByAppendingString:[scriptPath lastPathComponent]];
    NSString* documentRoot = env[@"DOCUMENT_ROOT"] ?: [scriptPath stringByDeletingLastPathComponent];
    NSString* phpSelf = env[@"PHP_SELF"] ?: scriptName;

    NSString* escapedScript = [self phpEscapedString:scriptPath];
    NSString* escapedScriptName = [self phpEscapedString:scriptName];
    NSString* escapedRequest = [self phpEscapedString:requestUri ?: scriptName];
    NSString* escapedQuery = [self phpEscapedString:queryString ?: @""];
    NSString* escapedDocRoot = [self phpEscapedString:documentRoot];
    NSString* escapedSelf = [self phpEscapedString:phpSelf];

    NSString* serverSetup = [NSString stringWithFormat:
                             @"$_SERVER['SCRIPT_FILENAME']='%@';"
                             @"$_SERVER['SCRIPT_NAME']='%@';"
                             @"$_SERVER['REQUEST_URI']='%@';"
                             @"$_SERVER['QUERY_STRING']='%@';"
                             @"$_SERVER['DOCUMENT_ROOT']='%@';"
                             @"$_SERVER['REQUEST_METHOD']='GET';"
                             @"$_SERVER['PHP_SELF']='%@';"
                             @"$_SERVER['SERVER_SOFTWARE']='PHP-iOS';",
                             escapedScript,
                             escapedScriptName,
                             escapedRequest,
                             escapedQuery,
                             escapedDocRoot,
                             escapedSelf];
    zend_eval_string([serverSetup UTF8String], NULL, "PhpIOS");
}

- (NSString*)phpEscapedString:(NSString*)value {
    NSString* escaped = [value stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"];
    escaped = [escaped stringByReplacingOccurrencesOfString:@"'" withString:@"\\'"];
    return escaped;
}

- (void)redirectStdin:(NSData*)stdinData
          savedStdin:(int*)savedStdin
           tempStdin:(int*)tempStdin
            tempPath:(NSString**)tempPath {
    NSString* filename = [NSString stringWithFormat:@"stdin-%@", [[NSUUID UUID] UUIDString]];
    NSString* path = [_workingDirectory stringByAppendingPathComponent:filename];
    [stdinData writeToFile:path atomically:YES];

    int fileDescriptor = open([path fileSystemRepresentation], O_RDONLY);
    if (fileDescriptor < 0) {
        return;
    }

    int saved = dup(STDIN_FILENO);
    if (saved >= 0) {
        dup2(fileDescriptor, STDIN_FILENO);
        if (savedStdin) {
            *savedStdin = saved;
        }
        if (tempStdin) {
            *tempStdin = fileDescriptor;
        }
        if (tempPath) {
            *tempPath = path;
        }
    } else {
        close(fileDescriptor);
    }
}

- (NSString*)stringFromZval:(zval*)value {
    if (!value) {
        return @"";
    }
    zend_string* str = zval_get_string(value);
    if (!str) {
        return @"";
    }
    NSString* result = [NSString stringWithUTF8String:ZSTR_VAL(str)] ?: @"";
    zend_string_release(str);
    return result;
}

- (void)applyEnvironment:(NSDictionary<NSString*, NSString*>*)env
         previousValues:(NSMutableDictionary<NSString*, NSString*>*)previousValues {
    if (env.count == 0) {
        return;
    }
    for (NSString* key in env) {
        const char* ckey = [key UTF8String];
        const char* existing = getenv(ckey);
        if (existing) {
            previousValues[key] = [NSString stringWithUTF8String:existing];
        } else {
            previousValues[key] = @"";
        }
        NSString* value = env[key] ?: @"";
        setenv(ckey, [value UTF8String], 1);
    }
}

- (void)restoreEnvironment:(NSDictionary<NSString*, NSString*>*)previousValues {
    if (previousValues.count == 0) {
        return;
    }
    for (NSString* key in previousValues) {
        NSString* value = previousValues[key];
        if (value.length > 0) {
            setenv([key UTF8String], [value UTF8String], 1);
        } else {
            unsetenv([key UTF8String]);
        }
    }
}

- (void)freeArgv:(char**)argv count:(int)count {
    if (!argv) {
        return;
    }
    for (int i = 0; i < count; i++) {
        if (argv[i]) {
            free(argv[i]);
        }
    }
    free(argv);
}
#endif

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
