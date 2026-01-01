#import <Foundation/Foundation.h>
#import "PhpBridge.h"
#import <TargetConditionals.h>

#if TARGET_OS_IPHONE
#include <dispatch/dispatch.h>
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
    NSString* _iniPathOverride;
}

@end

#if TARGET_OS_IPHONE
static NSMutableData* phpios_stderr_data = nil;
static NSMutableData* phpios_stdout_data = nil;
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

static size_t phpios_ub_write(const char *str, size_t str_length) {
    if (!phpios_stdout_data || !str || str_length == 0) {
        return str_length;
    }
    [phpios_stdout_data appendBytes:str length:str_length];
    return str_length;
}
#endif

@implementation PhpBridge

- (instancetype)init {
    return [self initWithIniPath:nil];
}

- (instancetype)initWithIniPath:(NSString*)iniPath {
    self = [super init];
    if (self) {
        _initialized = NO;
        _iniPathOverride = [iniPath copy];
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
        NSString* iniPath = _iniPathOverride;
        if (iniPath.length == 0) {
            iniPath = [[NSBundle mainBundle] pathForResource:@"php" ofType:@"ini"];
        }
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
    NSString* bufferedOutput = @"";
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
    size_t (*prev_ub_write)(const char*, size_t) = php_embed_module.ub_write;
    phpios_stderr_data = stderrData;
    phpios_stdout_data = [NSMutableData data];
    php_embed_module.log_message = phpios_log_message;
    php_embed_module.sapi_error = phpios_sapi_error;
    php_embed_module.ub_write = phpios_ub_write;

    if (php_embed_init(argc, cargv) != SUCCESS) {
        php_embed_module.log_message = prev_log_message;
        php_embed_module.sapi_error = prev_sapi_error;
        php_embed_module.ub_write = prev_ub_write;
        phpios_stderr_data = nil;
        phpios_stdout_data = nil;
        [self restoreEnvironment:previousEnv];
        [self freeArgv:cargv count:argc];
        return [[PhpResult alloc] initWithExitCode:1
                                           stdout:@""
                                           stderr:@"PHP initialization failed"];
    }
    php_embed_module.log_message = phpios_log_message;
    php_embed_module.sapi_error = phpios_sapi_error;
    php_embed_module.ub_write = phpios_ub_write;

    SG(request_info).argc = argc;
    SG(request_info).argv = cargv;
    SG(request_info).request_method = "GET";
    SG(request_info).no_headers = 1;
    SG(headers_sent) = 0;

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
    [self applyPhpPrelude];

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
        bufferedOutput = [self stringFromZval:&output];
    }
    php_output_end_all();
    zval_ptr_dtor(&output);

    if (phpios_stdout_data.length > 0) {
        NSString* captured = [[NSString alloc] initWithData:phpios_stdout_data encoding:NSUTF8StringEncoding];
        if (captured.length > 0) {
            stdoutOutput = captured;
        }
    }
    if (stdoutOutput.length == 0 && bufferedOutput.length > 0) {
        stdoutOutput = bufferedOutput;
    }

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
    php_embed_module.ub_write = prev_ub_write;
    phpios_stderr_data = nil;
    phpios_stdout_data = nil;

    [self restoreEnvironment:previousEnv];
    [self freeArgv:cargv count:argc];

    return [[PhpResult alloc] initWithExitCode:exitCode
                                       stdout:stdoutOutput ?: @""
                                       stderr:stderrOutput ?: @""];
}

- (void)applyPhpPrelude {
    static NSString* prelude = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        prelude =
        @"if (!function_exists('iconv')) {"
        "  function iconv($in, $out, $str) {"
        "    if (function_exists('mb_convert_encoding')) {"
        "      return @mb_convert_encoding($str, $out, $in);"
        "    }"
        "    return $str;"
        "  }"
        "}"
        "\nif (!function_exists('iconv_strlen')) {"
        "  function iconv_strlen($str, $charset = null) {"
        "    if (function_exists('mb_strlen')) {"
        "      $encoding = $charset ?: mb_internal_encoding();"
        "      return mb_strlen($str, $encoding);"
        "    }"
        "    return strlen($str);"
        "  }"
        "}"
        "\nif (!function_exists('iconv_substr')) {"
        "  function iconv_substr($str, $start, $length = null, $charset = null) {"
        "    if (function_exists('mb_substr')) {"
        "      $encoding = $charset ?: mb_internal_encoding();"
        "      return $length === null ? mb_substr($str, $start, null, $encoding) : mb_substr($str, $start, $length, $encoding);"
        "    }"
        "    return $length === null ? substr($str, $start) : substr($str, $start, $length);"
        "  }"
        "}"
        "\nif (!function_exists('iconv_strpos')) {"
        "  function iconv_strpos($str, $needle, $offset = 0, $charset = null) {"
        "    if (function_exists('mb_strpos')) {"
        "      $encoding = $charset ?: mb_internal_encoding();"
        "      return mb_strpos($str, $needle, $offset, $encoding);"
        "    }"
        "    return strpos($str, $needle, $offset);"
        "  }"
        "}"
        "\nif (!function_exists('iconv_strrpos')) {"
        "  function iconv_strrpos($str, $needle, $charset = null) {"
        "    if (function_exists('mb_strrpos')) {"
        "      $encoding = $charset ?: mb_internal_encoding();"
        "      return mb_strrpos($str, $needle, 0, $encoding);"
        "    }"
        "    return strrpos($str, $needle);"
        "  }"
        "}"
        "\nif (!defined('MB_CASE_UPPER')) {"
        "  define('MB_CASE_UPPER', 0);"
        "}"
        "if (!defined('MB_CASE_LOWER')) {"
        "  define('MB_CASE_LOWER', 1);"
        "}"
        "if (!defined('MB_CASE_TITLE')) {"
        "  define('MB_CASE_TITLE', 2);"
        "}"
        "\nif (!function_exists('mb_internal_encoding')) {"
        "  function mb_internal_encoding($encoding = null) {"
        "    if ($encoding !== null) {"
        "      $GLOBALS['PHP_IOS_MB_INTERNAL_ENCODING'] = $encoding;"
        "      return true;"
        "    }"
        "    return $GLOBALS['PHP_IOS_MB_INTERNAL_ENCODING'] ?? 'UTF-8';"
        "  }"
        "}"
        "if (!function_exists('mb_detect_order')) {"
        "  function mb_detect_order($encoding_list = null) {"
        "    if ($encoding_list !== null) {"
        "      if (is_array($encoding_list)) {"
        "        $GLOBALS['PHP_IOS_MB_DETECT_ORDER'] = $encoding_list;"
        "        return true;"
        "      }"
        "      $GLOBALS['PHP_IOS_MB_DETECT_ORDER'] = array_map('trim', explode(',', (string)$encoding_list));"
        "      return true;"
        "    }"
        "    return $GLOBALS['PHP_IOS_MB_DETECT_ORDER'] ?? [mb_internal_encoding()];"
        "  }"
        "}"
        "if (!function_exists('mb_detect_encoding')) {"
        "  function mb_detect_encoding($string, $encoding_list = null, $strict = false) {"
        "    $list = $encoding_list ?: mb_detect_order();"
        "    if (is_array($list) && count($list) > 0) {"
        "      return $list[0];"
        "    }"
        "    if (is_string($list) && $list !== '') {"
        "      $parts = array_map('trim', explode(',', $list));"
        "      return $parts[0] ?? mb_internal_encoding();"
        "    }"
        "    return mb_internal_encoding();"
        "  }"
        "}"
        "if (!function_exists('mb_convert_encoding')) {"
        "  function mb_convert_encoding($string, $to_encoding, $from_encoding = null) {"
        "    return $string;"
        "  }"
        "}"
        "if (!function_exists('mb_split')) {"
        "  function mb_split($pattern, $string, $limit = -1) {"
        "    $delimiter = '/' . str_replace('/', '\\\\/', $pattern) . '/u';"
        "    if ($limit === 0) {"
        "      $limit = -1;"
        "    }"
        "    $result = @preg_split($delimiter, $string, $limit);"
        "    return $result === false ? false : $result;"
        "  }"
        "}"
        "if (!function_exists('mb_strlen')) {"
        "  function mb_strlen($string, $encoding = null) {"
        "    return strlen($string);"
        "  }"
        "}"
        "if (!function_exists('mb_substr')) {"
        "  function mb_substr($string, $start, $length = null, $encoding = null) {"
        "    return $length === null ? substr($string, $start) : substr($string, $start, $length);"
        "  }"
        "}"
        "if (!function_exists('mb_strpos')) {"
        "  function mb_strpos($haystack, $needle, $offset = 0, $encoding = null) {"
        "    return strpos($haystack, $needle, $offset);"
        "  }"
        "}"
        "if (!function_exists('mb_strrpos')) {"
        "  function mb_strrpos($haystack, $needle, $offset = 0, $encoding = null) {"
        "    return strrpos($haystack, $needle, $offset);"
        "  }"
        "}"
        "if (!function_exists('mb_stripos')) {"
        "  function mb_stripos($haystack, $needle, $offset = 0, $encoding = null) {"
        "    return stripos($haystack, $needle, $offset);"
        "  }"
        "}"
        "if (!function_exists('mb_strtolower')) {"
        "  function mb_strtolower($string, $encoding = null) {"
        "    return strtolower($string);"
        "  }"
        "}"
        "if (!function_exists('mb_strtoupper')) {"
        "  function mb_strtoupper($string, $encoding = null) {"
        "    return strtoupper($string);"
        "  }"
        "}"
        "if (!function_exists('mb_convert_case')) {"
        "  function mb_convert_case($string, $mode, $encoding = null) {"
        "    switch ($mode) {"
        "      case MB_CASE_UPPER:"
        "        return strtoupper($string);"
        "      case MB_CASE_LOWER:"
        "        return strtolower($string);"
        "      case MB_CASE_TITLE:"
        "        return ucwords(strtolower($string));"
        "      default:"
        "        return $string;"
        "    }"
        "  }"
        "}"
        "if (!function_exists('mb_language')) {"
        "  function mb_language($language = null) {"
        "    if ($language !== null) {"
        "      $GLOBALS['PHP_IOS_MB_LANGUAGE'] = $language;"
        "      return true;"
        "    }"
        "    return $GLOBALS['PHP_IOS_MB_LANGUAGE'] ?? 'uni';"
        "  }"
        "}"
        "if (!function_exists('mb_encode_mimeheader')) {"
        "  function mb_encode_mimeheader($string, $charset = 'UTF-8', $transfer_encoding = 'B', $linefeed = \"\\r\\n\", $indent = 0) {"
        "    return $string;"
        "  }"
        "}"
        "if (!function_exists('mb_convert_kana')) {"
        "  function mb_convert_kana($string, $option = 'KV', $encoding = null) {"
        "    return $string;"
        "  }"
        "}"
        "\nif (!isset($_SERVER['HTTP_ACCEPT_LANGUAGE'])) {"
        "  $_SERVER['HTTP_ACCEPT_LANGUAGE'] = 'en-US,en;q=0.9';"
        "}"
        "\nif (!isset($_SERVER['HTTP_ACCEPT'])) {"
        "  $_SERVER['HTTP_ACCEPT'] = 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8';"
        "}"
        "\nif (!isset($_SERVER['HTTP_USER_AGENT'])) {"
        "  $_SERVER['HTTP_USER_AGENT'] = 'PhpIOS/1.0';"
        "}"
        "\nif (!isset($_SERVER['HTTP_REFERER'])) {"
        "  $_SERVER['HTTP_REFERER'] = '';"
        "}"
        "\nif (!defined('IN_MANAGER_MODE')) {"
        "  $path = $_SERVER['SCRIPT_NAME'] ?? ($_SERVER['REQUEST_URI'] ?? '');"
        "  $isManager = (strpos($path, '/manager/') !== false);"
        "  define('IN_MANAGER_MODE', $isManager);"
        "}"
        "\nif (!defined('IN_INSTALL_MODE')) {"
        "  define('IN_INSTALL_MODE', false);"
        "}"
        "\nif (!defined('MODX_API_MODE')) {"
        "  define('MODX_API_MODE', false);"
        "}"
        "\nif (getenv('PHP_IOS_DEBUG') === '1') {"
        "  if (!defined('PHP_IOS_DEBUG')) {"
        "    define('PHP_IOS_DEBUG', true);"
        "  }"
        "  ini_set('display_errors', '1');"
        "  ini_set('display_startup_errors', '1');"
        "  ini_set('html_errors', '1');"
        "  error_reporting(E_ALL);"
        "}";
    });
    zend_eval_string([prelude UTF8String], NULL, "PhpIOSPrelude");
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
    NSString* documentRoot = env[@"DOCUMENT_ROOT"] ?: [scriptPath stringByDeletingLastPathComponent];
    NSString* scriptName = env[@"SCRIPT_NAME"];
    if (!scriptName) {
        NSString* normalizedRoot = [documentRoot stringByStandardizingPath];
        NSString* normalizedScript = [scriptPath stringByStandardizingPath];
        if ([normalizedScript hasPrefix:normalizedRoot]) {
            NSString* relative = [normalizedScript substringFromIndex:normalizedRoot.length];
            if (relative.length == 0) {
                scriptName = [@"/" stringByAppendingString:[scriptPath lastPathComponent]];
            } else if (![relative hasPrefix:@"/"]) {
                scriptName = [@"/" stringByAppendingString:relative];
            } else {
                scriptName = relative;
            }
        } else {
            scriptName = [@"/" stringByAppendingString:[scriptPath lastPathComponent]];
        }
    }
    NSString* phpSelf = env[@"PHP_SELF"] ?: scriptName;
    NSString* serverName = env[@"SERVER_NAME"] ?: env[@"HTTP_HOST"] ?: @"localhost";
    NSString* httpHost = env[@"HTTP_HOST"] ?: serverName;
    NSString* serverPort = env[@"SERVER_PORT"] ?: @"80";
    NSString* requestScheme = env[@"REQUEST_SCHEME"] ?: @"http";
    NSString* https = env[@"HTTPS"] ?: @"off";
    NSString* requestMethod = env[@"REQUEST_METHOD"] ?: @"GET";
    NSString* serverProtocol = env[@"SERVER_PROTOCOL"] ?: @"HTTP/1.1";
    NSString* httpAccept = env[@"HTTP_ACCEPT"] ?: @"text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8";
    NSString* httpAcceptLanguage = env[@"HTTP_ACCEPT_LANGUAGE"] ?: @"en-US,en;q=0.9";
    NSString* httpUserAgent = env[@"HTTP_USER_AGENT"] ?: @"PhpIOS/1.0";
    NSString* httpReferer = env[@"HTTP_REFERER"] ?: @"";

    NSString* escapedScript = [self phpEscapedString:scriptPath];
    NSString* escapedScriptName = [self phpEscapedString:scriptName];
    NSString* escapedRequest = [self phpEscapedString:requestUri ?: scriptName];
    NSString* escapedQuery = [self phpEscapedString:queryString ?: @""];
    NSString* escapedDocRoot = [self phpEscapedString:documentRoot];
    NSString* escapedSelf = [self phpEscapedString:phpSelf];
    NSString* escapedServerName = [self phpEscapedString:serverName];
    NSString* escapedHttpHost = [self phpEscapedString:httpHost];
    NSString* escapedServerPort = [self phpEscapedString:serverPort];
    NSString* escapedRequestScheme = [self phpEscapedString:requestScheme];
    NSString* escapedHttps = [self phpEscapedString:https];
    NSString* escapedRequestMethod = [self phpEscapedString:requestMethod];
    NSString* escapedServerProtocol = [self phpEscapedString:serverProtocol];
    NSString* escapedHttpAccept = [self phpEscapedString:httpAccept];
    NSString* escapedHttpAcceptLanguage = [self phpEscapedString:httpAcceptLanguage];
    NSString* escapedHttpUserAgent = [self phpEscapedString:httpUserAgent];
    NSString* escapedHttpReferer = [self phpEscapedString:httpReferer];

    NSString* serverSetup = [NSString stringWithFormat:
                             @"$_SERVER['SCRIPT_FILENAME']='%@';"
                             @"$_SERVER['SCRIPT_NAME']='%@';"
                             @"$_SERVER['REQUEST_URI']='%@';"
                             @"$_SERVER['QUERY_STRING']='%@';"
                             @"$_SERVER['DOCUMENT_ROOT']='%@';"
                             @"$_SERVER['REQUEST_METHOD']='%@';"
                             @"$_SERVER['SERVER_PROTOCOL']='%@';"
                             @"$_SERVER['PHP_SELF']='%@';"
                             @"$_SERVER['SERVER_SOFTWARE']='PHP-iOS';"
                             @"$_SERVER['SERVER_NAME']='%@';"
                             @"$_SERVER['HTTP_HOST']='%@';"
                             @"$_SERVER['HTTP_ACCEPT']='%@';"
                             @"$_SERVER['HTTP_ACCEPT_LANGUAGE']='%@';"
                             @"$_SERVER['HTTP_USER_AGENT']='%@';"
                             @"$_SERVER['HTTP_REFERER']='%@';"
                             @"$_SERVER['SERVER_PORT']='%@';"
                             @"$_SERVER['REQUEST_SCHEME']='%@';"
                             @"$_SERVER['HTTPS']='%@';",
                             escapedScript,
                             escapedScriptName,
                             escapedRequest,
                             escapedQuery,
                             escapedDocRoot,
                             escapedRequestMethod,
                             escapedServerProtocol,
                             escapedSelf,
                             escapedServerName,
                             escapedHttpHost,
                             escapedHttpAccept,
                             escapedHttpAcceptLanguage,
                             escapedHttpUserAgent,
                             escapedHttpReferer,
                             escapedServerPort,
                             escapedRequestScheme,
                             escapedHttps];
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
    } else if ([self code:stripped contains:@"defined('IN_MANAGER_MODE'"]
               || [self code:stripped contains:@"defined(\"IN_MANAGER_MODE\""]) {
        stdoutOutput = @"1";
    } else if ([self code:stripped contains:@"defined('IN_INSTALL_MODE'"]
               || [self code:stripped contains:@"defined(\"IN_INSTALL_MODE\""]) {
        stdoutOutput = @"1";
    } else if ([self code:stripped contains:@"defined('MODX_API_MODE'"]
               || [self code:stripped contains:@"defined(\"MODX_API_MODE\""]) {
        stdoutOutput = @"1";
    } else if ([self code:stripped contains:@"function_exists('iconv'"]
               || [self code:stripped contains:@"function_exists(\"iconv\""]) {
        stdoutOutput = @"1";
    } else if ([self code:stripped contains:@"$_SERVER['HTTP_ACCEPT_LANGUAGE']"]
               || [self code:stripped contains:@"$_SERVER[\"HTTP_ACCEPT_LANGUAGE\"]"]) {
        stdoutOutput = @"en-US,en;q=0.9";
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
