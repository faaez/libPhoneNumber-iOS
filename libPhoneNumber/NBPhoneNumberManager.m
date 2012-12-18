//
//  M2PhoneNumber.m
//  Band
//
//  Created by ishtar on 12. 12. 11..
//  Copyright (c) 2012년 NHN. All rights reserved.
//

#import "NBPhoneNumberManager.h"
#import "NBPhoneNumber.h"
#import "NBNumberFormat.h"
#import "NBPhoneNumberDesc.h"
#import "NBPhoneMetaData.h"
#import "M2PhoneMetaDataGenerator.h"
#import "math.h"


#pragma mark - Static Int variables -
const static int MIN_LENGTH_FOR_NSN_ = 2;
const static int MAX_LENGTH_FOR_NSN_ = 16;
const static int MAX_LENGTH_COUNTRY_CODE_ = 3;
const static int MAX_INPUT_STRING_LENGTH_ = 250;


#pragma mark - Static String variables -
NSString *INVALID_COUNTRY_CODE_STR = @"Invalid country calling code";
NSString *NOT_A_NUMBER_STR = @"The string supplied did not seem to be a phone number";
NSString *TOO_SHORT_AFTER_IDD_STR = @"Phone number too short after IDD";
NSString *TOO_SHORT_NSN_STR = @"The string supplied is too short to be a phone number";
NSString *TOO_LONG_STR = @"The string supplied is too long to be a phone number";

NSString *NANPA_COUNTRY_CODE_ = @"1";
NSString *UNKNOWN_REGION_ = @"ZZ";
NSString *COLOMBIA_MOBILE_TO_FIXED_LINE_PREFIX_ = @"3";
NSString *PLUS_SIGN = @"\\+";
NSString *STAR_SIGN_ = @"\\*";
NSString *PLUS_CHARS_ = @"+\uFF0B";
NSString *RFC3966_EXTN_PREFIX_ = @";ext=";
NSString *RFC3966_PREFIX_ = @"tel:";
NSString *RFC3966_PHONE_CONTEXT_ = @";phone-context=";
NSString *RFC3966_ISDN_SUBADDRESS_ = @";isub=";
NSString *DEFAULT_EXTN_PREFIX_ = @" ext. ";
NSString *REGION_CODE_FOR_NON_GEO_ENTITY = @"001";
NSString *VALID_ALPHA_ = @"A-Za-z";
NSString *VALID_DIGITS_ = @"0-9\uFF10-\uFF19\u0660-\u0669\u06F0-\u06F9";
NSString *VALID_PUNCTUATION = @"-x\u2010-\u2015\u2212\u30FC\uFF0D-\uFF0F \u00A0\u00AD\u200B\u2060\u3000()\uFF08\uFF09\uFF3B\uFF3D.\\[\\]/~\u2053\u223C\uFF5E";

#pragma mark - Static regular expression strings -
NSString *NON_DIGITS_PATTERN_ = @"\\D+";
NSString *CC_PATTERN_ = @"\\$CC";
NSString *FIRST_GROUP_PATTERN_ = @"(\\$\\d)";
NSString *SEPARATOR_PATTERN_ = @"[%@]+";
NSString *FIRST_GROUP_ONLY_PREFIX_PATTERN_ = @"^\\(?\\$1\\)?$";
NSString *NP_PATTERN_ = @"\\$NP";
NSString *FG_PATTERN_ = @"\\$FG";
NSString *VALID_ALPHA_PHONE_PATTERN_ = @"(?:.*?[A-Za-z]){3}.*";
NSString *UNIQUE_INTERNATIONAL_PREFIX_ = @"[\\d]+(?:[~\u2053\u223C\uFF5E][\\d]+)?";


#pragma mark - NBPhoneNumberManager interface -
@interface NBPhoneNumberManager ()

/*
 Terminologies
 - Country Number (CN)  = Country code for i18n calling
 - Country Code   (CC) : ISO country codes (2 chars)
 Ref. site (countrycode.org)
*/
@property (nonatomic, strong, readonly) NSDictionary *coreMetaData;
@property (nonatomic, strong, readonly) NSRegularExpression *PLUS_CHARS_PATTERN, *SEPARATOR_PATTERN_, *CAPTURING_DIGIT_PATTERN, *VALID_ALPHA_PHONE_PATTERN_, *VALID_START_CHAR_PATTERN_, *SECOND_NUMBER_START_PATTERN_;
@property (nonatomic, strong, readonly) NSRegularExpression *UNWANTED_END_CHAR_PATTERN_, *VALID_PHONE_NUMBER_PATTERN_;
@property (nonatomic, strong, readonly) NSString *LEADING_PLUS_CHARS_PATTERN_, *EXTN_PATTERN_;

@property (nonatomic, strong, readonly) NSDictionary *ALPHA_MAPPINGS_, *ALL_NORMALIZATION_MAPPINGS_, *DIGIT_MAPPINGS, *DIALLABLE_CHAR_MAPPINGS_, *ALL_PLUS_NUMBER_GROUPING_SYMBOLS_;

@property (nonatomic, strong, readwrite) NSMutableDictionary *mapCCode2CN;
@property (nonatomic, strong, readwrite) NSMutableDictionary *mapCN2CCode;

@property (nonatomic, strong, readwrite) NSMutableDictionary *i18nNumberFormat;
@property (nonatomic, strong, readwrite) NSMutableDictionary *i18nPhoneNumberDesc;
@property (nonatomic, strong, readwrite) NSMutableDictionary *i18nPhoneMetadata;

@end


@implementation NBPhoneNumberManager

+ (NBPhoneNumberManager*)sharedInstance
{
    static NBPhoneNumberManager *sharedOnceInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ sharedOnceInstance = [[self alloc] init]; });
    return sharedOnceInstance;
}


#pragma mark - Utilities -
- (BOOL)hasValue:(NSString*)string
{
    if (string == nil || [string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].length <= 0)
    {
        return NO;
    }
    
    return YES;
}


- (NSArray*)componentsSeparatedByRegex:(NSString*)sourceString regex:(NSString*)pattern
{
    NSMutableArray *resArray = [[NSMutableArray alloc] init];
    NSError *error = nil;
    
    int previousPosition = 0;
    
    NSRegularExpression *currentPattern = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:&error];
    NSArray *matches = [currentPattern matchesInString:sourceString options:0 range:NSMakeRange(0, sourceString.length)];
    
    for(NSTextCheckingResult *match in matches)
    {
        int currentPosition = match.range.location;
        
        /*
        if (currentPosition <= previousPosition)
        {
            continue;
        }
        */
        
        NSString *subString = [sourceString substringWithRange:NSMakeRange(previousPosition, currentPosition)];
        NSLog(@"-componentsSeparatedByRegex [%@]", subString);
        
        if ([self hasValue:subString])
        {
            [resArray addObject:subString];
        }
        
        //previousPosition = match.range.location + match.range.length;
    }
    
    return resArray;
}


- (int)stringPositionByRegex:(NSString*)sourceString regex:(NSString*)pattern
{
    NSError *error = nil;
    NSRegularExpression *currentPattern = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:&error];
    NSArray *matches = [currentPattern matchesInString:sourceString options:0 range:NSMakeRange(0, sourceString.length)];
    
    int foundPosition = -1;
    
    for(NSTextCheckingResult *match in matches)
    {
        foundPosition = match.range.location;
        if (foundPosition >= 0)
        {
            break;
        }
    }
    
    return foundPosition;
}


- (int)indexOfStringByString:(NSString*)sourceString target:(NSString*)targetString
{
    NSRange finded = [sourceString rangeOfString:targetString];
    if (finded.location != NSNotFound)
    {
        return finded.location;
    }
    
    return -1;
}


- (NSString*)replaceStringByRegex:(NSString*)sourceString regex:(NSString*)pattern withTemplate:(NSString*)templateString
{
    NSString *replacementResult = nil;
    NSError *error = nil;
    
    NSRegularExpression *currentPattern = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:&error];

    replacementResult = [currentPattern stringByReplacingMatchesInString:[sourceString mutableCopy] options:0
                                                                   range:NSMakeRange(0, sourceString.length)
                                                            withTemplate:templateString];
    
    return replacementResult;
}


- (NSArray*)matchesByRegex:(NSString*)sourceString regex:(NSString*)pattern
{
    NSError *error = nil;
    NSRegularExpression *currentPattern = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:&error];
    NSArray *matches = [currentPattern matchesInString:sourceString options:0 range:NSMakeRange(0, sourceString.length)];
    return matches;
}


- (BOOL)isStartingStringByRegex:(NSString*)sourceString regex:(NSString*)pattern
{
    NSError *error = nil;
    NSRegularExpression *currentPattern = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:&error];
    NSArray *matches = [currentPattern matchesInString:sourceString options:0 range:NSMakeRange(0, sourceString.length)];
    
    for (NSTextCheckingResult *match in matches)
    {
        if (match.range.location == 0)
        {
            return YES;
        }
    }
    
    return NO;
}


- (NSString*)stringByReplacingOccurrencesString:(NSString *)sourceString withMap:(NSDictionary *)dicMap removeNonMatches:(BOOL)bRemove
{
    NSMutableString *targetString = [[NSMutableString alloc] init];
    
    for(int i=0; i<sourceString.length; i++)
    {
        unichar oneChar = [sourceString characterAtIndex:i];
        NSString *keyString = [NSString stringWithCharacters:&oneChar length:1];
        NSString *mappedValue = [dicMap valueForKey:keyString];
        if (mappedValue)
        {
            [targetString stringByAppendingString:mappedValue];
        }
        else
        {
            if (bRemove == NO)
            {
                [targetString stringByAppendingString:keyString];
            }
        }
    }
    
    return targetString;
}


- (BOOL)isNaN:(NSString*)sourceString
{
    NSCharacterSet *alphaNums = [NSCharacterSet decimalDigitCharacterSet];
    NSCharacterSet *inStringSet = [NSCharacterSet characterSetWithCharactersInString:sourceString];
    BOOL hasNumberOnly = [alphaNums isSupersetOfSet:inStringSet];
    
    return !hasNumberOnly;
}


- (NSString*)numbersOnly:(NSString*)phoneNumber
{
    NSMutableString *strippedString = [NSMutableString stringWithCapacity:phoneNumber.length];
    
    NSScanner *scanner = [NSScanner scannerWithString:phoneNumber];
    NSCharacterSet *numbers = [NSCharacterSet characterSetWithCharactersInString:@"0123456789"];
    
    while ([scanner isAtEnd] == NO) {
        NSString *buffer;
        if ([scanner scanCharactersFromSet:numbers intoString:&buffer]) {
            [strippedString appendString:buffer];
            
        } else {
            [scanner setScanLocation:([scanner scanLocation] + 1)];
        }
    }
    
    return strippedString;
}


- (NSString*)getNationalSignificantNumber:(NBPhoneNumber*)phoneNumber
{
    if (phoneNumber.italianLeadingZero)
    {
        return [NSString stringWithFormat:@"0%@", phoneNumber.nationalNumber];
    }
    
    return phoneNumber.nationalNumber;
}


- (NSArray*)regionCodeFromCountryCode:(NSString*)countryCodeNumber
{
    if (self.mapCN2CCode == nil || [self.mapCN2CCode count] <= 0)
    {
        return nil;
    }
    
    id res = [self.mapCN2CCode objectForKey:countryCodeNumber];
    
    if (res && [res isKindOfClass:[NSArray class]] && [((NSArray*)res) count] > 0)
    {
        return res;
    }
    
    return nil;
}


- (NSString*)countryCodeFromRregionCode:(NSString*)regionCode
{
    if (self.mapCCode2CN == nil || [self.mapCCode2CN count] <= 0)
    {
        return nil;
    }
    
    id res = [self.mapCCode2CN objectForKey:regionCode];
    
    if (res)
    {
        return res;
    }
    
    return nil;
}


#pragma mark - Initializations -
- (id)init
{
    self = [super init];
    if (self)
    {
        [self initRegularExpressionSet];
        [self initNormalizationMappings];
        
        M2PhoneMetaDataGenerator *pnGen = [[M2PhoneMetaDataGenerator alloc] init];
        _coreMetaData = [pnGen generateMetaData];
        
        [self initCC2CN];
        [self initCN2CC];
    }
    
    return self;
}


- (void)initRegularExpressionSet
{ 
    NSString *VALID_PHONE_NUMBER_ = [NSString stringWithFormat:@"[%@]*(?:[%@%@]*[*%@]){3,}[%@%@%@%@]*", PLUS_CHARS_, VALID_PUNCTUATION, STAR_SIGN_, VALID_DIGITS_, VALID_PUNCTUATION, STAR_SIGN_, VALID_ALPHA_, VALID_DIGITS_];
    
    /*
    VALID_PHONE_NUMBER_ = [NSString stringWithFormat:@"[+\uFF0B]*(?:[-x\u2010-\u2015\u2212\u30FC\uFF0D-\uFF0F \u00A0\u00AD\u200B\u2060\u3000()\uFF08\uFF09\uFF3B\uFF3D.\\[\\]/~\u2053\u223C\uFF5E%@]*[0-9\uFF10-\uFF19\u0660-\u0669\u06F0-\u06F9]){3,}[-x\u2010-\u2015\u2212\u30FC\uFF0D-\uFF0F \u00A0\u00AD\u200B\u2060\u3000()\uFF08\uFF09\uFF3B\uFF3D.\\[\\]/~\u2053\u223C\uFF5E%@A-Za-z0-9\uFF10-\uFF19\u0660-\u0669\u06F0-\u06F9]*", STAR_SIGN_, STAR_SIGN_];
     */
    
    NSString *CAPTURING_EXTN_DIGITS_ = [NSString stringWithFormat:@"([%@]{1,7})", VALID_DIGITS_];
    
    NSString *EXTN_PATTERNS_FOR_PARSING_ = [NSString stringWithFormat:@"%@%@|[ \u00A0\\t,]*(?:e?xt(?:ensi(?:o\u0301?|\u00F3))?n?|\uFF45?\uFF58\uFF54\uFF4E?|[,x\uFF58#\uFF03~\uFF5E]|int|anexo|\uFF49\uFF4E\uFF54)[:\\.\uFF0E]?[ \u00A0\\t,-]*%@#?|[- ]+([%@]{1,5})#",
                                            RFC3966_EXTN_PREFIX_, CAPTURING_EXTN_DIGITS_, CAPTURING_EXTN_DIGITS_, VALID_DIGITS_];
    
    NSString *MIN_LENGTH_PHONE_NUMBER_PATTERN_ = [NSString stringWithFormat:@"[%@]{%d}", VALID_DIGITS_, MIN_LENGTH_FOR_NSN_];
    
    NSError *error = nil;
    
    _PLUS_CHARS_PATTERN =
        [NSRegularExpression regularExpressionWithPattern:[NSString stringWithFormat:@"[%@]+", PLUS_CHARS_] options:0 error:&error];
    
    _LEADING_PLUS_CHARS_PATTERN_ = [NSString stringWithFormat:@"^[%@]+", PLUS_CHARS_];
    
    _CAPTURING_DIGIT_PATTERN =
        [NSRegularExpression regularExpressionWithPattern:[NSString stringWithFormat:@"([%@])", VALID_DIGITS_] options:0 error:&error];
    
    _VALID_START_CHAR_PATTERN_ =
        [NSRegularExpression regularExpressionWithPattern:[NSString stringWithFormat:@"[%@%@]", PLUS_CHARS_, VALID_DIGITS_] options:0 error:&error];
    
    _SECOND_NUMBER_START_PATTERN_ =
        [NSRegularExpression regularExpressionWithPattern:@"[\\\\\\/] *x" options:0 error:&error];
    
    _UNWANTED_END_CHAR_PATTERN_ =
        [NSRegularExpression regularExpressionWithPattern:[NSString stringWithFormat:@"[^%@%@#]+$", VALID_DIGITS_, VALID_ALPHA_]
                                                  options:0 error:&error];
    
    _EXTN_PATTERN_ = [NSString stringWithFormat:@"(?:%@)$", EXTN_PATTERNS_FOR_PARSING_];

    
    _VALID_PHONE_NUMBER_PATTERN_ =
        [NSRegularExpression regularExpressionWithPattern:[NSString stringWithFormat:@"^%@$|^%@(?:%@)?$", MIN_LENGTH_PHONE_NUMBER_PATTERN_, VALID_PHONE_NUMBER_, EXTN_PATTERNS_FOR_PARSING_]
                                                  options:0 error:&error];
}


- (void)dealloc
{
    [self clearCC2CN];
    [self clearCN2CC];
}


- (void)clearCC2CN
{
    if (self.mapCCode2CN != nil)
    {
        [self.mapCCode2CN removeAllObjects];
        self.mapCCode2CN = nil;
    }
}


- (void)clearCN2CC
{
    if (self.mapCN2CCode != nil)
    {
        [self.mapCN2CCode removeAllObjects];
        self.mapCN2CCode = nil;
    }
}


- (void)initNormalizationMappings
{
    _DIGIT_MAPPINGS = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                       @"0", @"0", @"1", @"1", @"2", @"2", @"3", @"3", @"4", @"4", @"5", @"5", @"6", @"6", @"7", @"7", @"8", @"8", @"9", @"9",
                       // Fullwidth digit 0 to 9
                       @"0", @"\uFF10", @"1", @"\uFF11", @"2", @"\uFF12", @"3", @"\uFF13", @"4", @"\uFF14", @"5", @"\uFF15", @"6", @"\uFF16", @"7", @"\uFF17", @"8", @"\uFF18", @"9", @"\uFF19",
                       // Arabic-indic digit 0 to 9
                       @"0", @"\u0660", @"1", @"\u0661", @"2", @"\u0662", @"3", @"\u0663", @"4", @"\u0664", @"5", @"\u0665", @"6", @"\u0666", @"7", @"\u0667", @"8", @"\u0668", @"9", @"\u0669",
                       // Eastern-Arabic digit 0 to 9
                       @"0", @"\u06F0", @"1", @"\u06F1",  @"2", @"\u06F2", @"3", @"\u06F3", @"4", @"\u06F4", @"5", @"\u06F5", @"6", @"\u06F6", @"7", @"\u06F7", @"8", @"\u06F8", @"9", @"\u06F9", nil];
    
    _DIALLABLE_CHAR_MAPPINGS_ = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                 @"0", @"0", @"1", @"1", @"2", @"2", @"3", @"3", @"4", @"4", @"5", @"5", @"6", @"6", @"7", @"7", @"8", @"8", @"9", @"9",
                                 @"+", @"+", @"*", @"*", nil];
    
    _ALPHA_MAPPINGS_ = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                        @"2", @"A", @"2", @"B", @"2", @"C", @"3", @"D", @"3", @"E", @"3", @"F", @"4", @"G", @"4", @"H", @"4", @"I", @"5", @"J",
                        @"5", @"K", @"5", @"L", @"6", @"M", @"6", @"N", @"6", @"O", @"7", @"P", @"7", @"Q", @"7", @"R", @"7", @"S", @"8", @"T",
                        @"8", @"U", @"8", @"V", @"9", @"W", @"9", @"X", @"9", @"Y", @"9", @"Z", nil];
    
    _ALL_NORMALIZATION_MAPPINGS_ = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                    @"0", @"0", @"1", @"1", @"2", @"2", @"3", @"3", @"4", @"4", @"5", @"5", @"6", @"6", @"7", @"7", @"8", @"8", @"9", @"9",
                                    // Fullwidth digit 0 to 9
                                    @"0", @"\uFF10", @"1", @"\uFF11", @"2", @"\uFF12", @"3", @"\uFF13", @"4", @"\uFF14", @"5", @"\uFF15", @"6", @"\uFF16", @"7", @"\uFF17", @"8", @"\uFF18", @"9", @"\uFF19",
                                    // Arabic-indic digit 0 to 9
                                    @"0", @"\u0660", @"1", @"\u0661", @"2", @"\u0662", @"3", @"\u0663", @"4", @"\u0664", @"5", @"\u0665", @"6", @"\u0666", @"7", @"\u0667", @"8", @"\u0668", @"9", @"\u0669",
                                    // Eastern-Arabic digit 0 to 9
                                    @"0", @"\u06F0", @"1", @"\u06F1",  @"2", @"\u06F2", @"3", @"\u06F3", @"4", @"\u06F4", @"5", @"\u06F5", @"6", @"\u06F6", @"7", @"\u06F7", @"8", @"\u06F8", @"9", @"\u06F9",
                                    @"2", @"A", @"2", @"B", @"2", @"C", @"3", @"D", @"3", @"E", @"3", @"F", @"4", @"G", @"4", @"H", @"4", @"I", @"5", @"J",
                                    @"5", @"K", @"5", @"L", @"6", @"M", @"6", @"N", @"6", @"O", @"7", @"P", @"7", @"Q", @"7", @"R", @"7", @"S", @"8", @"T",
                                    @"8", @"U", @"8", @"V", @"9", @"W", @"9", @"X", @"9", @"Y", @"9", @"Z", nil];
    
    _ALL_PLUS_NUMBER_GROUPING_SYMBOLS_ = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                          @"0", @"0", @"1", @"1", @"2", @"2", @"3", @"3", @"4", @"4", @"5", @"5", @"6", @"6", @"7", @"7", @"8", @"8", @"9", @"9",
                                          @"A", @"A", @"B", @"B", @"C", @"C", @"D", @"D", @"E", @"E", @"F", @"F", @"G", @"G", @"H", @"H", @"I", @"I", @"J", @"J",
                                          @"K", @"K", @"L", @"L", @"M", @"M", @"N", @"N", @"O", @"O", @"P", @"P", @"Q", @"Q", @"R", @"R", @"S", @"S", @"T", @"T",
                                          @"U", @"U", @"V", @"V", @"W", @"W", @"X", @"X", @"Y", @"Y", @"Z", @"Z", @"A", @"a", @"B", @"b", @"C", @"c", @"D", @"d",
                                          @"E", @"e", @"F", @"f", @"G", @"g", @"H", @"h", @"I", @"i", @"J", @"j", @"K", @"k", @"L", @"l", @"M", @"m", @"N", @"n",
                                          @"O", @"o", @"P", @"p", @"Q", @"q", @"R", @"r", @"S", @"s", @"T", @"t", @"U", @"u", @"V", @"v", @"W", @"w", @"X", @"x",
                                          @"Y", @"y", @"Z", @"z", @"-", @"-", @"-", @"\uFF0D", @"-", @"\u2010", @"-", @"\u2011", @"-", @"\u2012", @"-", @"\u2013", @"-", @"\u2014", @"-", @"\u2015",
                                          @"-", @"\u2212", @"/", @"/", @"/", @"\uFF0F", @" ", @" ", @" ", @"\u3000", @" ", @"\u2060", @".", @".", @".", @"\uFF0E", nil];

}


- (void)initCC2CN
{
    [self clearCC2CN];
    _mapCCode2CN = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                    @"1", @"US", @"1", @"AG", @"1", @"AI", @"1", @"AS", @"1", @"BB", @"1", @"BM", @"1", @"BS", @"1", @"CA", @"1", @"DM", @"1", @"DO",
                    @"1", @"GD", @"1", @"GU", @"1", @"JM", @"1", @"KN", @"1", @"KY", @"1", @"LC", @"1", @"MP", @"1", @"MS", @"1", @"PR", @"1", @"SX",
                    @"1", @"TC", @"1", @"TT", @"1", @"VC", @"1", @"VG", @"1", @"VI", @"7", @"RU", @"7", @"KZ",
                    @"20", @"EG", @"27", @"ZA",
                    @"30", @"GR", @"31", @"NL", @"32", @"BE", @"33", @"FR", @"34", @"ES", @"36", @"HU", @"39", @"IT",
                    @"40", @"RO", @"41", @"CH", @"43", @"AT", @"44", @"GB", @"44", @"GG", @"44", @"IM", @"44", @"JE", @"45", @"DK", @"46", @"SE", @"47", @"NO", @"47", @"SJ", @"48", @"PL", @"49", @"DE",
                    @"51", @"PE", @"52", @"MX", @"53", @"CU", @"54", @"AR", @"55", @"BR", @"56", @"CL", @"57", @"CO", @"58", @"VE",
                    @"60", @"MY", @"61", @"AU", @"61", @"CC", @"61", @"CX", @"62", @"ID", @"63", @"PH", @"64", @"NZ", @"65", @"SG", @"66", @"TH",
                    @"81", @"JP", @"82", @"KR", @"84", @"VN", @"86", @"CN",
                    @"90", @"TR", @"91", @"IN", @"92", @"PK", @"93", @"AF", @"94", @"LK", @"95", @"MM", @"98", @"IR",
                    @"211", @"SS", @"212", @"MA", @"212", @"EH", @"213", @"DZ", @"216", @"TN", @"218", @"LY",
                    @"220", @"GM", @"221", @"SN", @"222", @"MR", @"223", @"ML", @"224", @"GN", @"225", @"CI", @"226", @"BF", @"227", @"NE", @"228", @"TG", @"229", @"BJ",
                    @"230", @"MU", @"231", @"LR", @"232", @"SL", @"233", @"GH", @"234", @"NG", @"235", @"TD", @"236", @"CF", @"237", @"CM", @"238", @"CV", @"239", @"ST",
                    @"240", @"GQ", @"241", @"GA", @"242", @"CG", @"243", @"CD", @"244", @"AO", @"245", @"GW", @"246", @"IO", @"247", @"AC", @"248", @"SC", @"249", @"SD",
                    @"250", @"RW", @"251", @"ET", @"252", @"SO", @"253", @"DJ", @"254", @"KE", @"255", @"TZ", @"256", @"UG", @"257", @"BI", @"258", @"MZ",
                    @"260", @"ZM", @"261", @"MG", @"262", @"RE", @"262", @"YT", @"263", @"ZW", @"264", @"NA", @"265", @"MW", @"266", @"LS", @"267", @"BW", @"268", @"SZ", @"269", @"KM",
                    @"290", @"SH", @"291", @"ER", @"297", @"AW", @"298", @"FO", @"299", @"GL",
                    @"350", @"GI", @"351", @"PT", @"352", @"LU", @"353", @"IE", @"354", @"IS", @"355", @"AL", @"356", @"MT", @"357", @"CY", @"358", @"FI",@"358", @"AX", @"359", @"BG",
                    @"370", @"LT", @"371", @"LV", @"372", @"EE", @"373", @"MD", @"374", @"AM", @"375", @"BY", @"376", @"AD", @"377", @"MC", @"378", @"SM", @"379", @"VA",
                    @"380", @"UA", @"381", @"RS", @"382", @"ME", @"385", @"HR", @"386", @"SI", @"387", @"BA", @"389", @"MK",
                    @"420", @"CZ", @"421", @"SK", @"423", @"LI",
                    @"500", @"FK", @"501", @"BZ", @"502", @"GT", @"503", @"SV", @"504", @"HN", @"505", @"NI", @"506", @"CR", @"507", @"PA", @"508", @"PM", @"509", @"HT",
                    @"590", @"GP", @"590", @"BL", @"590", @"MF", @"591", @"BO", @"592", @"GY", @"593", @"EC", @"594", @"GF", @"595", @"PY", @"596", @"MQ", @"597", @"SR", @"598", @"UY", @"599", @"CW", @"599", @"BQ",
                    @"670", @"TL", @"672", @"NF", @"673", @"BN", @"674", @"NR", @"675", @"PG", @"676", @"TO", @"677", @"SB", @"678", @"VU", @"679", @"FJ",
                    @"680", @"PW", @"681", @"WF", @"682", @"CK", @"683", @"NU", @"685", @"WS", @"686", @"KI", @"687", @"NC", @"688", @"TV", @"689", @"PF",
                    @"690", @"TK", @"691", @"FM", @"692", @"MH",
                    @"800", @"001", @"808", @"001",
                    @"850", @"KP", @"852", @"HK", @"853", @"MO", @"855", @"KH", @"856", @"LA",
                    @"870", @"001", @"878", @"001",
                    @"880", @"BD", @"881", @"001", @"882", @"001", @"883", @"001", @"886", @"TW", @"888", @"001",
                    @"960", @"MV", @"961", @"LB", @"962", @"JO", @"963", @"SY", @"964", @"IQ", @"965", @"KW", @"966", @"SA", @"967", @"YE", @"968", @"OM",
                    @"970", @"PS", @"971", @"AE", @"972", @"IL", @"973", @"BH", @"974", @"QA", @"975", @"BT", @"976", @"MN", @"977", @"NP", @"979", @"001",
                    @"992", @"TJ", @"993", @"TM", @"994", @"AZ", @"995", @"GE", @"996", @"KG", @"998", @"UZ",
                    nil];
}


- (void)initCN2CC
{
    [self clearCN2CC];
    _mapCN2CCode = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                    @[@"US", @"AG", @"AI", @"AS", @"BB", @"BM", @"BS", @"CA", @"DM", @"DO", @"GD", @"GU", @"JM", @"KN", @"KY", @"LC", @"MP", @"MS", @"PR", @"SX", @"TC", @"TT", @"VC", @"VG", @"VI"], @"1", @[@"RU", @"KZ"], @"7",
                    @[@"EG"], @"20", @[@"ZA"], @"27",
                    @[@"GR"], @"30", @[@"NL"], @"31", @[@"BE"], @"32", @[@"FR"], @"33", @[@"ES"], @"34", @[@"HU"], @"36", @[@"IT"], @"39",
                    @[@"RO"], @"40", @[@"CH"], @"41", @[@"AT"], @"43", @[@"GB", @"GG", @"IM", @"JE"], @"44", @[@"DK"], @"45", @[@"SE"], @"46", @[@"NO", @"SJ"], @"47", @[@"PL"], @"48", @[@"DE"], @"49",
                    @[@"PE"], @"51", @[@"MX"], @"52", @[@"CU"], @"53", @[@"AR"], @"54", @[@"BR"], @"55", @[@"CL"], @"56", @[@"CO"], @"57", @[@"VE"], @"58",
                    @[@"MY"], @"60", @[@"AU", @"CC", @"CX"], @"61", @[@"ID"], @"62", @[@"PH"], @"63", @[@"NZ"], @"64", @[@"SG"], @"65", @[@"TH"], @"66",
                    @[@"JP"], @"81", @[@"KR"], @"82", @[@"VN"], @"84", @[@"CN"], @"86",
                    @[@"TR"], @"90", @[@"IN"], @"91", @[@"PK"], @"92", @[@"AF"], @"93", @[@"LK"], @"94", @[@"MM"], @"95", @[@"IR"], @"98",
                    @[@"SS"], @"211", @[@"MA", @"EH"], @"212", @[@"DZ"], @"213", @[@"TN"], @"216", @[@"LY"], @"218",
                    @[@"GM"], @"220", @[@"SN"], @"221", @[@"MR"], @"222", @[@"ML"], @"223", @[@"GN"], @"224", @[@"CI"], @"225", @[@"BF"], @"226", @[@"NE"], @"227", @[@"TG"], @"228", @[@"BJ"], @"229",
                    @[@"MU"], @"230", @[@"LR"], @"231", @[@"SL"], @"232", @[@"GH"], @"233", @[@"NG"], @"234", @[@"TD"], @"235", @[@"CF"], @"236", @[@"CM"], @"237", @[@"CV"], @"238", @[@"ST"], @"239",
                    @[@"GQ"], @"240", @[@"GA"], @"241", @[@"CG"], @"242", @[@"CD"], @"243", @[@"AO"], @"244", @[@"GW"], @"245", @[@"IO"], @"246", @[@"AC"], @"247", @[@"SC"], @"248", @[@"SD"], @"249",
                    @[@"RW"], @"250", @[@"ET"], @"251", @[@"SO"], @"252", @[@"DJ"], @"253", @[@"KE"], @"254", @[@"TZ"], @"255", @[@"UG"], @"256", @[@"BI"], @"257", @[@"MZ"], @"258",
                    @[@"ZM"], @"260", @[@"MG"], @"261", @[@"RE", @"YT"], @"262", @[@"ZW"], @"263", @[@"NA"], @"264", @[@"MW"], @"265", @[@"LS"], @"266", @[@"BW"], @"267", @[@"SZ"], @"268", @[@"KM"], @"269",
                    @[@"SH"], @"290", @[@"ER"], @"291", @[@"AW"], @"297", @[@"FO"], @"298", @[@"GL"], @"299",
                    @[@"GI"], @"350", @[@"PT"], @"351", @[@"LU"], @"352", @[@"IE"], @"353", @[@"IS"], @"354", @[@"AL"], @"355", @[@"MT"], @"356", @[@"CY"], @"357", @[@"FI", @"AX"], @"358", @[@"BG"], @"359",
                    @[@"LT"], @"370", @[@"LV"], @"371", @[@"EE"], @"372", @[@"MD"], @"373", @[@"AM"], @"374", @[@"BY"], @"375", @[@"AD"], @"376", @[@"MC"], @"377", @[@"SM"], @"378", @[@"VA"], @"379",
                    @[@"UA"], @"380", @[@"RS"], @"381", @[@"ME"], @"382", @[@"HR"], @"385", @[@"SI"], @"386", @[@"BA"], @"387", @[@"MK"], @"389",
                    @[@"CZ"], @"420", @[@"SK"], @"421", @[@"LI"], @"423",
                    @[@"FK"], @"500", @[@"BZ"], @"501", @[@"GT"], @"502", @[@"SV"], @"503", @[@"HN"], @"504", @[@"NI"], @"505", @[@"CR"], @"506", @[@"PA"], @"507", @[@"PM"], @"508", @[@"HT"], @"509",
                    @[@"GP", @"BL", @"MF"], @"590", @[@"BO"], @"591", @[@"GY"], @"592", @[@"EC"], @"593", @[@"GF"], @"594", @[@"PY"], @"595", @[@"MQ"], @"596", @[@"SR"], @"597", @[@"UY"], @"598", @[@"CW", @"BQ"], @"599",
                    @[@"TL"], @"670", @[@"NF"], @"672", @[@"BN"], @"673", @[@"NR"], @"674", @[@"PG"], @"675", @[@"TO"], @"676", @[@"SB"], @"677", @[@"VU"], @"678", @[@"FJ"], @"679",
                    @[@"PW"], @"680", @[@"WF"], @"681", @[@"CK"], @"682", @[@"NU"], @"683", @[@"WS"], @"685", @[@"KI"], @"686", @[@"NC"], @"687", @[@"TV"], @"688", @[@"PF"], @"689",
                    @[@"TK"], @"690", @[@"FM"], @"691", @[@"MH"], @"692",
                    @[@"001"], @"800", @[@"001"], @"808",
                    @[@"KP"], @"850", @[@"HK"], @"852", @[@"MO"], @"853", @[@"KH"], @"855", @[@"LA"], @"856",
                    @[@"001"], @"870", @[@"001"], @"878",
                    @[@"BD"], @"880", @[@"001"], @"881", @[@"001"], @"882", @[@"001"], @"883", @[@"TW"], @"886", @[@"001"], @"888",
                    @[@"MV"], @"960", @[@"LB"], @"961", @[@"JO"], @"962", @[@"SY"], @"963", @[@"IQ"], @"964", @[@"KW"], @"965", @[@"SA"], @"966", @[@"YE"], @"967", @[@"OM"], @"968",
                    @[@"PS"], @"970", @[@"AE"], @"971", @[@"IL"], @"972", @[@"BH"], @"973", @[@"QA"], @"974", @[@"BT"], @"975", @[@"MN"], @"976", @[@"NP"], @"977", @[@"001"], @"979",
                    @[@"TJ"], @"992", @[@"TM"], @"993", @[@"AZ"], @"994", @[@"GE"], @"995", @[@"KG"], @"996", @[@"UZ"], @"998", nil];
}


#pragma mark - Metadata manager (phonenumberutil.js) functions -
/**
 * Attempts to extract a possible number from the string passed in. This
 * currently strips all leading characters that cannot be used to start a phone
 * number. Characters that can be used to start a phone number are defined in
 * the VALID_START_CHAR_PATTERN. If none of these characters are found in the
 * number passed in, an empty string is returned. This function also attempts to
 * strip off any alternative extensions or endings if two or more are present,
 * such as in the case of: (530) 583-6985 x302/x2303. The second extension here
 * makes this actually two phone numbers, (530) 583-6985 x302 and (530) 583-6985
 * x2303. We remove the second extension so that the first number is parsed
 * correctly.
 *
 * @param {string} number the string that might contain a phone number.
 * @return {string} the number, stripped of any non-phone-number prefix (such as
 *     'Tel:') or an empty string if no character used to start phone numbers
 *     (such as + or any digit) is found in the number.
 */
- (NSString*)extractPossibleNumber:(NSString*)phoneNumber
{
    NSString *possibleNumber = @"";
    NSRegularExpression *currentPattern = self.VALID_START_CHAR_PATTERN_;
    int sourceLength = phoneNumber.length;
    
    NSArray *matches = [currentPattern matchesInString:phoneNumber options:0 range:NSMakeRange(0, sourceLength)];
    if (matches && [matches count] > 0)
    {
        NSRange rangeOfFirstMatch = ((NSTextCheckingResult*)[matches objectAtIndex:0]).range;
        possibleNumber = [phoneNumber substringWithRange:NSMakeRange(rangeOfFirstMatch.location, sourceLength - rangeOfFirstMatch.location)];
        
        // Remove trailing non-alpha non-numerical characters.
        currentPattern = self.UNWANTED_END_CHAR_PATTERN_;
        possibleNumber = [currentPattern stringByReplacingMatchesInString:possibleNumber options:0
                                                                    range:NSMakeRange(0, [possibleNumber length]) withTemplate:@""];
        // Check for extra numbers at the end.
        currentPattern = self.SECOND_NUMBER_START_PATTERN_;
        matches = [currentPattern matchesInString:possibleNumber options:0
                                            range:NSMakeRange(0, [possibleNumber length])];
        if (matches && [matches count] > 0)
        {
            NSRange rangeOfSecondMatch = ((NSTextCheckingResult*)[matches objectAtIndex:0]).range;
            possibleNumber = [possibleNumber substringWithRange:NSMakeRange(0, rangeOfSecondMatch.location)];
        }
    }
    
    return possibleNumber;
}


/**
 * Checks to see if the string of characters could possibly be a phone number at
 * all. At the moment, checks to see that the string begins with at least 2
 * digits, ignoring any punctuation commonly found in phone numbers. This method
 * does not require the number to be normalized in advance - but does assume
 * that leading non-number symbols have been removed, such as by the method
 * extractPossibleNumber.
 *
 * @param {string} number string to be checked for viability as a phone number.
 * @return {boolean} NO if the number could be a phone number of some sort,
 *     otherwise NO.
 */
- (BOOL)isViablePhoneNumber:(NSString*)phoneNumber
{
    if (phoneNumber.length < MIN_LENGTH_FOR_NSN_)
    {
        return NO;
    }
    
    NSRegularExpression *currentPattern = self.VALID_PHONE_NUMBER_PATTERN_;
    NSArray *matches = [currentPattern matchesInString:phoneNumber options:0 range:NSMakeRange(0, phoneNumber.length)];
    
    if (matches && [matches count] > 0)
    {
        NSTextCheckingResult *currentMatch = [matches objectAtIndex:0];
        NSString *founds = [phoneNumber substringWithRange:currentMatch.range];
        NSLog(@"isViablePhoneNumbe matches [%@]", founds);
        return [founds isEqualToString:phoneNumber];
    }
    
    return NO;
}


/**
 * Normalizes a string of characters representing a phone number. This performs
 * the following conversions:
 *   Punctuation is stripped.
 *   For ALPHA/VANITY numbers:
 *   Letters are converted to their numeric representation on a telephone
 *       keypad. The keypad used here is the one defined in ITU Recommendation
 *       E.161. This is only done if there are 3 or more letters in the number,
 *       to lessen the risk that such letters are typos.
 *   For other numbers:
 *   Wide-ascii digits are converted to normal ASCII (European) digits.
 *   Arabic-Indic numerals are converted to European numerals.
 *   Spurious alpha characters are stripped.
 *
 * @param {string} number a string of characters representing a phone number.
 * @return {string} the normalized string version of the phone number.
 */
- (NSString*)normalizePhoneNumber:(NSString*)phoneNumber
{
    NSRegularExpression *currentPattern = self.VALID_ALPHA_PHONE_PATTERN_;
    NSArray *matches = [currentPattern matchesInString:phoneNumber options:0 range:NSMakeRange(0, phoneNumber.length)];
    
    if (matches && [matches count] > 0)
    {
        NSTextCheckingResult *currentMatch = [matches objectAtIndex:0];
        NSString *founds = [phoneNumber substringWithRange:currentMatch.range];
        
        if ([founds isEqualToString:phoneNumber])
        {
            return [self stringByReplacingOccurrencesString:founds withMap:self.ALL_NORMALIZATION_MAPPINGS_ removeNonMatches:YES];
        }
        else
        {
            return [self normalizeDigitsOnly:founds];
        }
    }
    
    return nil;
}


/**
 * Normalizes a string of characters representing a phone number. This is a
 * wrapper for normalize(String number) but does in-place normalization of the
 * StringBuffer provided.
 *
 * @param {!goog.string.StringBuffer} number a StringBuffer of characters
 *     representing a phone number that will be normalized in place.
 * @private
 */

- (NSString *)normalizeSB:(NSString*)number
{
    NSString *normalizedNumber = [self normalizePhoneNumber:number];
    return normalizedNumber;
}


/**
 * Normalizes a string of characters representing a phone number. This converts
 * wide-ascii and arabic-indic numerals to European numerals, and strips
 * punctuation and alpha characters.
 *
 * @param {string} number a string of characters representing a phone number.
 * @return {string} the normalized string version of the phone number.
 */
- (NSString*)normalizeDigitsOnly:(NSString*)number
{
    return [self stringByReplacingOccurrencesString:number
                                            withMap:self.DIGIT_MAPPINGS removeNonMatches:YES];
}


/**
 * Converts all alpha characters in a number to their respective digits on a
 * keypad, but retains existing formatting. Also converts wide-ascii digits to
 * normal ascii digits, and converts Arabic-Indic numerals to European numerals.
 *
 * @param {string} number a string of characters representing a phone number.
 * @return {string} the normalized string version of the phone number.
 */
- (NSString*)convertAlphaCharactersInNumber:(NSString*)number
{
    return [self stringByReplacingOccurrencesString:number
                                            withMap:self.ALL_NORMALIZATION_MAPPINGS_ removeNonMatches:NO];
}


/**
 * Gets the length of the geographical area code from the
 * {@code national_number} field of the PhoneNumber object passed in, so that
 * clients could use it to split a national significant number into geographical
 * area code and subscriber number. It works in such a way that the resultant
 * subscriber number should be diallable, at least on some devices. An example
 * of how this could be used:
 *
 * <pre>
 * var phoneUtil = getInstance();
 * var number = phoneUtil.parse('16502530000', 'US');
 * var nationalSignificantNumber =
 *     phoneUtil.getNationalSignificantNumber(number);
 * var areaCode;
 * var subscriberNumber;
 *
 * var areaCodeLength = phoneUtil.getLengthOfGeographicalAreaCode(number);
 * if (areaCodeLength > 0) {
 *   areaCode = nationalSignificantNumber.substring(0, areaCodeLength);
 *   subscriberNumber = nationalSignificantNumber.substring(areaCodeLength);
 * } else {
 *   areaCode = '';
 *   subscriberNumber = nationalSignificantNumber;
 * }
 * </pre>
 *
 * N.B.: area code is a very ambiguous concept, so the I18N team generally
 * recommends against using it for most purposes, but recommends using the more
 * general {@code national_number} instead. Read the following carefully before
 * deciding to use this method:
 * <ul>
 *  <li> geographical area codes change over time, and this method honors those
 *    changes; therefore, it doesn't guarantee the stability of the result it
 *    produces.
 *  <li> subscriber numbers may not be diallable from all devices (notably
 *    mobile devices, which typically requires the full national_number to be
 *    dialled in most regions).
 *  <li> most non-geographical numbers have no area codes, including numbers
 *    from non-geographical entities.
 *  <li> some geographical numbers have no area codes.
 * </ul>
 *
 * @param {i18n.phonenumbers.PhoneNumber} number the PhoneNumber object for
 *     which clients want to know the length of the area code.
 * @return {number} the length of area code of the PhoneNumber object passed in.
 */
- (int)getLengthOfGeographicalAreaCode:(NBPhoneNumber*)phoneNumber
{
    NSString *regionCode = [self getRegionCodeForNumber:phoneNumber];
    NBPhoneMetaData *metadata = [self getMetadataForRegion:regionCode];
    
    if (metadata == nil)
    {
        return 0;
    }
    // If a country doesn't use a national prefix, and this number doesn't have
    // an Italian leading zero, we assume it is a closed dialling plan with no
    // area codes.
    if (metadata.nationalPrefix == nil && phoneNumber.italianLeadingZero == NO)
    {
        return 0;
    }
    
    if ([self isNumberGeographical:phoneNumber] == NO)
    {
        return 0;
    }
    
    return [self getLengthOfNationalDestinationCode:phoneNumber];
}


/**
* Gets the length of the national destination code (NDC) from the PhoneNumber
* object passed in, so that clients could use it to split a national
* significant number into NDC and subscriber number. The NDC of a phone number
* is normally the first group of digit(s) right after the country calling code
* when the number is formatted in the international format, if there is a
* subscriber number part that follows. An example of how this could be used:
*
* <pre>
* var phoneUtil = getInstance();
* var number = phoneUtil.parse('18002530000', 'US');
* var nationalSignificantNumber =
*     phoneUtil.getNationalSignificantNumber(number);
* var nationalDestinationCode;
* var subscriberNumber;
*
* var nationalDestinationCodeLength =
*     phoneUtil.getLengthOfNationalDestinationCode(number);
* if (nationalDestinationCodeLength > 0) {
    *   nationalDestinationCode =
    *       nationalSignificantNumber.substring(0, nationalDestinationCodeLength);
    *   subscriberNumber =
    *       nationalSignificantNumber.substring(nationalDestinationCodeLength);
    * } else {
        *   nationalDestinationCode = '';
        *   subscriberNumber = nationalSignificantNumber;
        * }
* </pre>
*
* Refer to the unittests to see the difference between this function and
* {@link #getLengthOfGeographicalAreaCode}.
*
* @param {i18n.phonenumbers.PhoneNumber} number the PhoneNumber object for
*     which clients want to know the length of the NDC.
* @return {number} the length of NDC of the PhoneNumber object passed in.
*/
- (int)getLengthOfNationalDestinationCode:(NBPhoneNumber*)phoneNumber
{
    NBPhoneNumber *copiedProto = nil;
    if ([self hasValue:phoneNumber.extension])
    {
        copiedProto = [phoneNumber copy];
        copiedProto.extension = nil;
    }
    else
    {
        copiedProto = phoneNumber;
    }
    
    NSString *nationalSignificantNumber = [self format:copiedProto numberFormat:INTERNATIONAL];
    NSMutableArray *numberGroups = [[self componentsSeparatedByRegex:nationalSignificantNumber regex:NON_DIGITS_PATTERN_] mutableCopy];
    
    // The pattern will start with '+COUNTRY_CODE ' so the first group will always
    // be the empty string (before the + symbol) and the second group will be the
    // country calling code. The third group will be area code if it is not the
    // last group.
    // NOTE: On IE the first group that is supposed to be the empty string does
    // not appear in the array of number groups... so make the result on non-IE
    // browsers to be that of IE.
    if ([numberGroups count] > 0 && ((NSString*)[numberGroups objectAtIndex:0]).length <= 0)
    {
        [numberGroups removeObjectAtIndex:0];
    }
    
    if ([numberGroups count] <= 2)
    {
        return 0;
    }
    
    NSArray *regionCodes = [self regionCodeFromCountryCode:phoneNumber.countryCode];
    BOOL isExists = NO;
    
    for (NSString *regCode in regionCodes)
    {
        if ([regCode isEqualToString:@"AR"])
        {
            isExists = YES;
            break;
        }
    }
    
    if (isExists && [self getNumberType:phoneNumber] == MOBILE)
    {
        // Argentinian mobile numbers, when formatted in the international format,
        // are in the form of +54 9 NDC XXXX.... As a result, we take the length of
        // the third group (NDC) and add 1 for the digit 9, which also forms part of
        // the national significant number.
        //
        // TODO: Investigate the possibility of better modeling the metadata to make
        // it easier to obtain the NDC.
        return ((NSString*)[numberGroups objectAtIndex:1]).length + 1;
    }
    
    return ((NSString*)[numberGroups objectAtIndex:0]).length;
}


/**
 * Normalizes a string of characters representing a phone number by replacing
 * all characters found in the accompanying map with the values therein, and
 * stripping all other characters if removeNonMatches is NO.
 *
 * @param {string} number a string of characters representing a phone number.
 * @param {!Object.<string, string>} normalizationReplacements a mapping of
 *     characters to what they should be replaced by in the normalized version
 *     of the phone number.
 * @param {boolean} removeNonMatches indicates whether characters that are not
 *     able to be replaced should be stripped from the number. If this is NO,
 *     they will be left unchanged in the number.
 * @return {string} the normalized string version of the phone number.
 * @private
 */
- (NSString*)normalizeHelper:(NSString*)sourceString normalizationReplacements:(NSDictionary*)normalizationReplacements
            removeNonMatches:(BOOL)removeNonMatches
{
    NSMutableString *normalizedNumber = [[NSMutableString alloc] init];
    unichar character = 0;
    NSString *newDigit = @"";
    int numberLength = sourceString.length;
    
    for (int i = 0; i<numberLength; ++i)
    {
        character = [sourceString characterAtIndex:i];
        newDigit = [normalizationReplacements valueForKey:[NSString stringWithFormat: @"%C", character]];
        if (newDigit != nil)
        {
            [normalizedNumber appendString:newDigit];
        }
        else if (removeNonMatches == NO)
        {
            [normalizedNumber appendString:[NSString stringWithFormat: @"%C", character]];
        }
        // If neither of the above are NO, we remove this character.
    }
    
    return normalizedNumber;
}


/**
 * Helper function to check if the national prefix formatting rule has the first
 * group only, i.e., does not start with the national prefix.
 *
 * @param {string} nationalPrefixFormattingRule The formatting rule for the
 *     national prefix.
 * @return {boolean} NO if the national prefix formatting rule has the first
 *     group only.
 */
- (BOOL)formattingRuleHasFirstGroupOnly:(NSString*)nationalPrefixFormattingRule
{
    BOOL hasFound = NO;
    if ([self stringPositionByRegex:nationalPrefixFormattingRule regex:FIRST_GROUP_ONLY_PREFIX_PATTERN_] >= 0)
    {
        hasFound = YES;
    }
    
    return hasFound;
}


/**
 * Tests whether a phone number has a geographical association. It checks if
 * the number is associated to a certain region in the country where it belongs
 * to. Note that this doesn't verify if the number is actually in use.
 *
 * @param {i18n.phonenumbers.PhoneNumber} phoneNumber The phone number to test.
 * @return {boolean} NO if the phone number has a geographical association.
 * @private
 */
- (BOOL)isNumberGeographical:(NBPhoneNumber*)phoneNumber
{
    NBEPhoneNumberType numberType = [self getNumberType:phoneNumber];
    // TODO: Include mobile phone numbers from countries like Indonesia, which
    // has some mobile numbers that are geographical.
    return numberType == FIXED_LINE || numberType == FIXED_LINE_OR_MOBILE;
}


/**
 * Helper function to check region code is not unknown or nil.
 *
 * @param {?string} regionCode the ISO 3166-1 two-letter region code.
 * @return {boolean} NO if region code is valid.
 * @private
 */
- (BOOL)isValidRegionCode:(NSString*)regionCode
{
    // In Java we check whether the regionCode is contained in supportedRegions
    // that is built out of all the values of countryCallingCodeToRegionCodeMap
    // (countryCodeToRegionCodeMap in JS) minus REGION_CODE_FOR_NON_GEO_ENTITY.
    // In JS we check whether the regionCode is contained in the keys of
    // countryToMetadata but since for non-geographical country calling codes
    // (e.g. +800) we use the country calling codes instead of the region code as
    // key in the map we have to make sure regionCode is not a number to prevent
    // returning NO for non-geographical country calling codes.
    return [self hasValue:regionCode] && [self isNaN:regionCode] && [self getMetadataForRegion:regionCode.uppercaseString] != nil;
}


/**
 * Helper function to check the country calling code is valid.
 *
 * @param {number} countryCallingCode the country calling code.
 * @return {boolean} NO if country calling code code is valid.
 * @private
 */
- (BOOL)hasValidCountryCallingCode:(NSString*)countryCallingCode
{
    id res = [self regionCodeFromCountryCode:countryCallingCode];
    if (res != nil)
    {
        return YES;
    }
    
    return NO;
}


/**
 * Formats a phone number in the specified format using default rules. Note that
 * this does not promise to produce a phone number that the user can dial from
 * where they are - although we do format in either 'national' or
 * 'international' format depending on what the client asks for, we do not
 * currently support a more abbreviated format, such as for users in the same
 * 'area' who could potentially dial the number without area code. Note that if
 * the phone number has a country calling code of 0 or an otherwise invalid
 * country calling code, we cannot work out which formatting rules to apply so
 * we return the national significant number with no formatting applied.
 *
 * @param {i18n.phonenumbers.PhoneNumber} number the phone number to be
 *     formatted.
 * @param {i18n.phonenumbers.PhoneNumberFormat} numberFormat the format the
 *     phone number should be formatted into.
 * @return {string} the formatted phone number.
 */
- (NSString*)format:(NBPhoneNumber*)phoneNumber numberFormat:(NBEPhoneNumberFormat)numberFormat
{
    if (phoneNumber.nationalNumber == 0 && phoneNumber.rawInput)
    {
        // Unparseable numbers that kept their raw input just use that.
        // This is the only case where a number can be formatted as E164 without a
        // leading '+' symbol (but the original number wasn't parseable anyway).
        // TODO: Consider removing the 'if' above so that unparseable strings
        // without raw input format to the empty string instead of "+00"
        /** @type {string} */
        NSString *rawInput = phoneNumber.rawInput;
        if ([self hasValue:rawInput]) {
            return rawInput;
        }
    }
    
    NSString *countryCallingCode = phoneNumber.countryCode;
    NSString *nationalSignificantNumber = [self getNationalSignificantNumber:phoneNumber];
    
    if (numberFormat == E164)
    {
        // Early exit for E164 case (even if the country calling code is invalid)
        // since no formatting of the national number needs to be applied.
        // Extensions are not formatted.
        return [self prefixNumberWithCountryCallingCode:countryCallingCode phoneNumberFormat:E164
                                formattedNationalNumber:nationalSignificantNumber formattedExtension:@""];
    }
    
    if ([self hasValidCountryCallingCode:countryCallingCode] == NO)
    {
        return nationalSignificantNumber;
    }
    
    // Note getRegionCodeForCountryCode() is used because formatting information
    // for regions which share a country calling code is contained by only one
    // region for performance reasons. For example, for NANPA regions it will be
    // contained in the metadata for US.
    NSArray *regionCodeArray = [self regionCodeFromCountryCode:countryCallingCode];
    NSString *regionCode = [regionCodeArray objectAtIndex:0];
    
    // Metadata cannot be nil because the country calling code is valid (which
    // means that the region code cannot be ZZ and must be one of our supported
    // region codes).
    NBPhoneMetaData *metadata = [self getMetadataForRegionOrCallingCode:countryCallingCode regionCode:regionCode];
    NSString *formattedExtension = [self maybeGetFormattedExtension:phoneNumber metadata:metadata numberFormat:numberFormat];
    NSString *formattedNationalNumber = [self formatNsn:nationalSignificantNumber metadata:metadata phoneNumberFormat:numberFormat carrierCode:nil];
    return [self prefixNumberWithCountryCallingCode:countryCallingCode phoneNumberFormat:numberFormat
                            formattedNationalNumber:formattedNationalNumber formattedExtension:formattedExtension];
}


/**
 * Formats a phone number in the specified format using client-defined
 * formatting rules. Note that if the phone number has a country calling code of
 * zero or an otherwise invalid country calling code, we cannot work out things
 * like whether there should be a national prefix applied, or how to format
 * extensions, so we return the national significant number with no formatting
 * applied.
 *
 * @param {i18n.phonenumbers.PhoneNumber} number the phone  number to be
 *     formatted.
 * @param {i18n.phonenumbers.PhoneNumberFormat} numberFormat the format the
 *     phone number should be formatted into.
 * @param {Array.<i18n.phonenumbers.NumberFormat>} userDefinedFormats formatting
 *     rules specified by clients.
 * @return {string} the formatted phone number.
 */
- (NSString*)formatByPattern:(NBPhoneNumber*)number numberFormat:(NBEPhoneNumberFormat)numberFormat userDefinedFormats:(NSArray*)userDefinedFormats
{
    NSString *countryCallingCode = number.countryCode;
    NSString *nationalSignificantNumber = [self getNationalSignificantNumber:number];
    
    if ([self hasValidCountryCallingCode:countryCallingCode] == NO)
    {
        return nationalSignificantNumber;
    }
    
    // Note getRegionCodeForCountryCode() is used because formatting information
    // for regions which share a country calling code is contained by only one
    // region for performance reasons. For example, for NANPA regions it will be
    // contained in the metadata for US.
    NSArray *regionCodes = [self regionCodeFromCountryCode:countryCallingCode];
    NSString *regionCode = nil;
    if (regionCodes != nil && regionCodes.count > 0)
    {
        regionCode = [regionCodes objectAtIndex:0];
    }
    
    // Metadata cannot be nil because the country calling code is valid
    /** @type {i18n.phonenumbers.PhoneMetadata} */
    NBPhoneMetaData *metadata = [self getMetadataForRegionOrCallingCode:countryCallingCode regionCode:regionCode];

    NSString *formattedNumber = @"";
    NBNumberFormat *formattingPattern = [self chooseFormattingPatternForNumber:userDefinedFormats nationalNumber:nationalSignificantNumber];
    if (formattingPattern == nil)
    {
        // If no pattern above is matched, we format the number as a whole.
        formattedNumber = nationalSignificantNumber;
    }
    else
    {
        // Before we do a replacement of the national prefix pattern $NP with the
        // national prefix, we need to copy the rule so that subsequent replacements
        // for different numbers have the appropriate national prefix.
        NBNumberFormat *numFormatCopy = [formattingPattern copy];
        NSString *nationalPrefixFormattingRule = formattingPattern.nationalPrefixFormattingRule;

        if (nationalPrefixFormattingRule.length > 0)
        {
            NSString *nationalPrefix = metadata.nationalPrefix;
            if (nationalPrefix.length > 0)
            {
                // Replace $NP with national prefix and $FG with the first group ($1).
                nationalPrefixFormattingRule = [self replaceStringByRegex:nationalPrefixFormattingRule regex:NP_PATTERN_ withTemplate:nationalPrefix];
                nationalPrefixFormattingRule = [self replaceStringByRegex:nationalPrefixFormattingRule regex:FG_PATTERN_ withTemplate:@"$1"];
                numFormatCopy.nationalPrefixFormattingRule = nationalPrefixFormattingRule;
            }
            else
            {
                // We don't want to have a rule for how to format the national prefix if
                // there isn't one.
                numFormatCopy.nationalPrefixFormattingRule = @"";
            }
        }
        
        formattedNumber = [self formatNsnUsingPattern:nationalSignificantNumber
                                    formattingPattern:numFormatCopy numberFormat:numberFormat carrierCode:nil];
    }
    
    NSString *formattedExtension = [self maybeGetFormattedExtension:number metadata:metadata numberFormat:numberFormat];
    
    return [self prefixNumberWithCountryCallingCode:countryCallingCode
                                  phoneNumberFormat:numberFormat
                            formattedNationalNumber:formattedNumber
                                 formattedExtension:formattedExtension];
}


/**
 * Formats a phone number in national format for dialing using the carrier as
 * specified in the {@code carrierCode}. The {@code carrierCode} will always be
 * used regardless of whether the phone number already has a preferred domestic
 * carrier code stored. If {@code carrierCode} contains an empty string, returns
 * the number in national format without any carrier code.
 *
 * @param {i18n.phonenumbers.PhoneNumber} number the phone number to be
 *     formatted.
 * @param {string} carrierCode the carrier selection code to be used.
 * @return {string} the formatted phone number in national format for dialing
 *     using the carrier as specified in the {@code carrierCode}.
 */
- (NSString*)formatNationalNumberWithCarrierCode:(NBPhoneNumber*)number carrierCode:(NSString*)carrierCode
{    
    NSString *countryCallingCode = number.countryCode;
    NSString *nationalSignificantNumber = [self getNationalSignificantNumber:number];
    if ([self hasValidCountryCallingCode:countryCallingCode])
    {
        return nationalSignificantNumber;
    }
    
    // Note getRegionCodeForCountryCode() is used because formatting information
    // for regions which share a country calling code is contained by only one
    // region for performance reasons. For example, for NANPA regions it will be
    // contained in the metadata for US.
    NSString *regionCode = [self getRegionCodeForCountryCode:countryCallingCode];
    // Metadata cannot be nil because the country calling code is valid.
    NBPhoneMetaData *metadata = [self getMetadataForRegionOrCallingCode:countryCallingCode regionCode:regionCode];
    NSString *formattedExtension = [self maybeGetFormattedExtension:number metadata:metadata numberFormat:NATIONAL];
    NSString *formattedNationalNumber = [self formatNsn:nationalSignificantNumber metadata:metadata phoneNumberFormat:NATIONAL carrierCode:carrierCode];
    return [self prefixNumberWithCountryCallingCode:countryCallingCode phoneNumberFormat:NATIONAL formattedNationalNumber:formattedNationalNumber formattedExtension:formattedExtension];
}


/**
 * @param {number} countryCallingCode
 * @param {?string} regionCode
 * @return {i18n.phonenumbers.PhoneMetadata}
 * @private
 */
- (NBPhoneMetaData*)getMetadataForRegionOrCallingCode:(NSString*)countryCallingCode regionCode:(NSString*)regionCode
{
    return [REGION_CODE_FOR_NON_GEO_ENTITY isEqualToString:regionCode] ?
        [self getMetadataForNonGeographicalRegion:countryCallingCode] : [self getMetadataForRegion:regionCode];
}


/**
 * Formats a phone number in national format for dialing using the carrier as
 * specified in the preferred_domestic_carrier_code field of the PhoneNumber
 * object passed in. If that is missing, use the {@code fallbackCarrierCode}
 * passed in instead. If there is no {@code preferred_domestic_carrier_code},
 * and the {@code fallbackCarrierCode} contains an empty string, return the
 * number in national format without any carrier code.
 *
 * <p>Use {@link #formatNationalNumberWithCarrierCode} instead if the carrier
 * code passed in should take precedence over the number's
 * {@code preferred_domestic_carrier_code} when formatting.
 *
 * @param {i18n.phonenumbers.PhoneNumber} number the phone number to be
 *     formatted.
 * @param {string} fallbackCarrierCode the carrier selection code to be used, if
 *     none is found in the phone number itself.
 * @return {string} the formatted phone number in national format for dialing
 *     using the number's preferred_domestic_carrier_code, or the
 *     {@code fallbackCarrierCode} passed in if none is found.
 */
- (NSString*)formatNationalNumberWithPreferredCarrierCode:(NBPhoneNumber*)number fallbackCarrierCode:(NSString*)fallbackCarrierCode
{
    NSString *domesticCarrierCode = [self hasValue:number.PreferredDomesticCarrierCode] ? number.PreferredDomesticCarrierCode : fallbackCarrierCode;
    return [self formatNationalNumberWithCarrierCode:number carrierCode:domesticCarrierCode];
}


/**
 * Returns a number formatted in such a way that it can be dialed from a mobile
 * phone in a specific region. If the number cannot be reached from the region
 * (e.g. some countries block toll-free numbers from being called outside of the
 * country), the method returns an empty string.
 *
 * @param {i18n.phonenumbers.PhoneNumber} number the phone number to be
 *     formatted.
 * @param {string} regionCallingFrom the region where the call is being placed.
 * @param {boolean} withFormatting whether the number should be returned with
 *     formatting symbols, such as spaces and dashes.
 * @return {string} the formatted phone number.
 */
- (NSString*)formatNumberForMobileDialing:(NBPhoneNumber*)number regionCallingFrom:(NSString*)regionCallingFrom withFormatting:(BOOL)withFormatting
{
    NSString *countryCallingCode = number.countryCode;
    if ([self hasValidCountryCallingCode:countryCallingCode] == NO)
    {
        return [self hasValue:number.rawInput] ? number.rawInput : @"";
    }
    
    NSString *formattedNumber = nil;
    // Clear the extension, as that part cannot normally be dialed together with
    // the main number.
    NBPhoneNumber *numberNoExt = [number copy];
    numberNoExt.extension = @"";
    NBEPhoneNumberType numberType = [self getNumberType:numberNoExt];

    NSString *regionCode = [self getRegionCodeForCountryCode:countryCallingCode];
    if ([regionCode isEqualToString:@"CO"] && [regionCallingFrom isEqualToString:@"CO"])
    {
        if (numberType == FIXED_LINE)
        {
            formattedNumber = [self formatNationalNumberWithCarrierCode:numberNoExt
                                                            carrierCode:COLOMBIA_MOBILE_TO_FIXED_LINE_PREFIX_];
        }
        else
        {
            // E164 doesn't work at all when dialing within Colombia.
            formattedNumber = [self format:numberNoExt numberFormat:NATIONAL];
        }
    }
    else if ([regionCode isEqualToString:@"PE"] && [regionCallingFrom isEqualToString:@"PE"])
    {
        // In Peru, numbers cannot be dialled using E164 format from a mobile phone
        // for Movistar. Instead they must be dialled in national format.
        formattedNumber = [self format:numberNoExt numberFormat:NATIONAL];
    }
    else if ([regionCode isEqualToString:@"BR"] && [regionCallingFrom isEqualToString:@"BR"] &&
               ((numberType == FIXED_LINE) || (numberType == MOBILE) || (numberType == FIXED_LINE_OR_MOBILE)))
    {
        formattedNumber = [self hasValue:numberNoExt.PreferredDomesticCarrierCode] ? [self formatNationalNumberWithPreferredCarrierCode:numberNoExt fallbackCarrierCode:@""] : @"";
        // Brazilian fixed line and mobile numbers need to be dialed with a
        // carrier code when called within Brazil. Without that, most of the
        // carriers won't connect the call. Because of that, we return an empty
        // string here.
    }
    else if ([self canBeInternationallyDialled:numberNoExt])
    {
        return withFormatting ? [self format:numberNoExt numberFormat:INTERNATIONAL] : [self format:numberNoExt numberFormat:E164];
    }
    else
    {
        formattedNumber = [regionCallingFrom isEqualToString:regionCode] ? [self format:numberNoExt numberFormat:NATIONAL] : @"";
    }
    
    return withFormatting ?
        formattedNumber : [self normalizeHelper:formattedNumber normalizationReplacements:self.DIALLABLE_CHAR_MAPPINGS_ removeNonMatches:YES];
}


/**
 * Formats a phone number for out-of-country dialing purposes. If no
 * regionCallingFrom is supplied, we format the number in its INTERNATIONAL
 * format. If the country calling code is the same as that of the region where
 * the number is from, then NATIONAL formatting will be applied.
 *
 * <p>If the number itself has a country calling code of zero or an otherwise
 * invalid country calling code, then we return the number with no formatting
 * applied.
 *
 * <p>Note this function takes care of the case for calling inside of NANPA and
 * between Russia and Kazakhstan (who share the same country calling code). In
 * those cases, no international prefix is used. For regions which have multiple
 * international prefixes, the number in its INTERNATIONAL format will be
 * returned instead.
 *
 * @param {i18n.phonenumbers.PhoneNumber} number the phone number to be
 *     formatted.
 * @param {string} regionCallingFrom the region where the call is being placed.
 * @return {string} the formatted phone number.
 */
- (NSString*)formatOutOfCountryCallingNumber:(NBPhoneNumber*)number regionCallingFrom:(NSString*)regionCallingFrom
{
    if ([self isValidRegionCode:regionCallingFrom] == NO)
    {
        return [self format:number numberFormat:INTERNATIONAL];
    }
    
    NSString *countryCallingCode = number.countryCode;
    NSString *nationalSignificantNumber = [self getNationalSignificantNumber:number];
    if ([self hasValidCountryCallingCode:countryCallingCode] == NO)
    {
        return nationalSignificantNumber;
    }
    
    if (countryCallingCode == NANPA_COUNTRY_CODE_)
    {
        if ([self isNANPACountry:regionCallingFrom])
        {
            // For NANPA regions, return the national format for these regions but
            // prefix it with the country calling code.
            return [NSString stringWithFormat:@"%@ %@", countryCallingCode, [self format:number numberFormat:NATIONAL]];
        }
    }
    else if (countryCallingCode == [self getCountryCodeForValidRegion:regionCallingFrom])
    {
        // If regions share a country calling code, the country calling code need
        // not be dialled. This also applies when dialling within a region, so this
        // if clause covers both these cases. Technically this is the case for
        // dialling from La Reunion to other overseas departments of France (French
        // Guiana, Martinique, Guadeloupe), but not vice versa - so we don't cover
        // this edge case for now and for those cases return the version including
        // country calling code. Details here:
        // http://www.petitfute.com/voyage/225-info-pratiques-reunion
        return [self format:number numberFormat:NATIONAL];
    }
    // Metadata cannot be nil because we checked 'isValidRegionCode()' above.
    NBPhoneMetaData *metadataForRegionCallingFrom = [self getMetadataForRegion:regionCallingFrom];
    NSString *internationalPrefix = metadataForRegionCallingFrom.internationalPrefix;
    
    // For regions that have multiple international prefixes, the international
    // format of the number is returned, unless there is a preferred international
    // prefix.
    NSString *internationalPrefixForFormatting = @"";
    if ([self matchesEntirely:UNIQUE_INTERNATIONAL_PREFIX_ string:internationalPrefix])
    {
        internationalPrefixForFormatting = internationalPrefix;
    }
    else if ([self hasValue:metadataForRegionCallingFrom.preferredInternationalPrefix])
    {
        internationalPrefixForFormatting = metadataForRegionCallingFrom.preferredInternationalPrefix;
    }
    
    NSString *regionCode = [self getRegionCodeForCountryCode:countryCallingCode];
    // Metadata cannot be nil because the country calling code is valid.
    NBPhoneMetaData *metadataForRegion = [self getMetadataForRegionOrCallingCode:countryCallingCode regionCode:regionCode];
    NSString *formattedNationalNumber = [self formatNsn:nationalSignificantNumber metadata:metadataForRegion
                                      phoneNumberFormat:INTERNATIONAL carrierCode:nil];
    NSString *formattedExtension = [self maybeGetFormattedExtension:number metadata:metadataForRegion numberFormat:INTERNATIONAL];

    NSString *hasLenth = [NSString stringWithFormat:@"%@ %@ %@%@", internationalPrefixForFormatting, countryCallingCode, formattedNationalNumber, formattedExtension];
    NSString *hasNotLength = [self prefixNumberWithCountryCallingCode:countryCallingCode phoneNumberFormat:INTERNATIONAL
                                              formattedNationalNumber:formattedNationalNumber formattedExtension:formattedExtension];
    
    return internationalPrefixForFormatting.length > 0 ? hasLenth:hasNotLength;
}

                                                                            
/**
 * A helper function that is used by format and formatByPattern.
 *
 * @param {number} countryCallingCode the country calling code.
 * @param {i18n.phonenumbers.PhoneNumberFormat} numberFormat the format the
 *     phone number should be formatted into.
 * @param {string} formattedNationalNumber
 * @param {string} formattedExtension
 * @return {string} the formatted phone number.
 * @private
 */
- (NSString*)prefixNumberWithCountryCallingCode:(NSString*)countryCallingCode phoneNumberFormat:(NBEPhoneNumberFormat)numberFormat
                        formattedNationalNumber:(NSString*)formattedNationalNumber
                             formattedExtension:(NSString*)formattedExtension
{
    switch (numberFormat)
    {
        case E164:
            return [NSString stringWithFormat:@"%@%@%@%@", @"+", countryCallingCode, formattedNationalNumber, formattedExtension];
        case INTERNATIONAL:
            return [NSString stringWithFormat:@"%@%@ %@%@", @"+", countryCallingCode, formattedNationalNumber, formattedExtension];
        case RFC3966:
            return [NSString stringWithFormat:@"%@%@%@-%@%@", RFC3966_PREFIX_, @"+", countryCallingCode, formattedNationalNumber, formattedExtension];
        case NATIONAL:
        default:
            return [NSString stringWithFormat:@"%@%@", formattedNationalNumber, formattedExtension];
    }
}


/**
 * Formats a phone number using the original phone number format that the number
 * is parsed from. The original format is embedded in the country_code_source
 * field of the PhoneNumber object passed in. If such information is missing,
 * the number will be formatted into the NATIONAL format by default. When the
 * number contains a leading zero and this is unexpected for this country, or we
 * don't have a formatting pattern for the number, the method returns the raw
 * input when it is available.
 *
 * Note this method guarantees no digit will be inserted, removed or modified as
 * a result of formatting.
 *
 * @param {i18n.phonenumbers.PhoneNumber} number the phone number that needs to
 *     be formatted in its original number format.
 * @param {string} regionCallingFrom the region whose IDD needs to be prefixed
 *     if the original number has one.
 * @return {string} the formatted phone number in its original number format.
 */
- (NSString*)formatInOriginalFormat:(NBPhoneNumber*)number regionCallingFrom:(NSString*)regionCallingFrom
{
    if ([self hasValue:number.rawInput] && ([self hasUnexpectedItalianLeadingZero:number] || [self hasFormattingPatternForNumber:number ] == NO))
    {
            // We check if we have the formatting pattern because without that, we might
            // format the number as a group without national prefix.
            return number.rawInput;
    }
    
    if (number.countryCodeSource != 0)
    {
        return [self format:number numberFormat:NATIONAL];
    }
    
    NSString *formattedNumber = @"";
    
    switch (number.countryCodeSource)
    {
        case FROM_NUMBER_WITH_PLUS_SIGN:
            formattedNumber = [self format:number numberFormat:INTERNATIONAL];
            break;
        case FROM_NUMBER_WITH_IDD:
            formattedNumber = [self formatOutOfCountryCallingNumber:number regionCallingFrom:regionCallingFrom];
            break;
        case FROM_NUMBER_WITHOUT_PLUS_SIGN:
            formattedNumber = [[self format:number numberFormat:INTERNATIONAL] substringToIndex:1];
            break;
        case FROM_DEFAULT_COUNTRY:
            // Fall-through to default case.
        default:
        {
            NSString *regionCode = [self getRegionCodeForCountryCode:number.countryCode];
            // We strip non-digits from the NDD here, and from the raw input later,
            // so that we can compare them easily.
            NSString *nationalPrefix = [self getNddPrefixForRegion:regionCode stripNonDigits:YES];
            NSString *nationalFormat = [self format:number numberFormat:NATIONAL];
            if (nationalPrefix == nil || nationalPrefix.length == 0)
            {
                // If the region doesn't have a national prefix at all, we can safely
                // return the national format without worrying about a national prefix
                // being added.
                formattedNumber = nationalFormat;
                break;
            }
            // Otherwise, we check if the original number was entered with a national
            // prefix.
            if ([self rawInputContainsNationalPrefix:number.rawInput nationalPrefix:nationalPrefix regionCode:regionCode])
            {
                // If so, we can safely return the national format.
                formattedNumber = nationalFormat;
                break;
            }
            // Metadata cannot be nil here because getNddPrefixForRegion() (above)
            // returns nil if there is no metadata for the region.
            NBPhoneMetaData *metadata = [self getMetadataForRegion:regionCode];
            NSString *nationalNumber = [self getNationalSignificantNumber:number];
            NBNumberFormat *formatRule = [self chooseFormattingPatternForNumber:metadata.numberFormats nationalNumber:nationalNumber];
            // The format rule could still be nil here if the national number was 0
            // and there was no raw input (this should not be possible for numbers
            // generated by the phonenumber library as they would also not have a
            // country calling code and we would have exited earlier).
            if (formatRule == nil)
            {
                formattedNumber = nationalFormat;
                break;
            }
            // When the format we apply to this number doesn't contain national
            // prefix, we can just return the national format.
            // TODO: Refactor the code below with the code in
            // isNationalPrefixPresentIfRequired.
            NSString *candidateNationalPrefixRule = formatRule.nationalPrefixFormattingRule;
            // We assume that the first-group symbol will never be _before_ the
            // national prefix.
            int indexOfFirstGroup = [self stringPositionByRegex:candidateNationalPrefixRule regex:@"$1"];
            if (indexOfFirstGroup <= 0)
            {
                formattedNumber = nationalFormat;
                break;
            }
            candidateNationalPrefixRule = [candidateNationalPrefixRule substringWithRange:NSMakeRange(0, indexOfFirstGroup)];
            candidateNationalPrefixRule = [self normalizeDigitsOnly:candidateNationalPrefixRule];
            if (candidateNationalPrefixRule.length == 0)
            {
                // National prefix not used when formatting this number.
                formattedNumber = nationalFormat;
                break;
            }
            // Otherwise, we need to remove the national prefix from our output.
            NBNumberFormat *numFormatCopy = [formatRule copy];
            numFormatCopy.nationalPrefixFormattingRule = nil;
            formattedNumber = [self formatByPattern:number numberFormat:NATIONAL userDefinedFormats:@[numFormatCopy]];
            break;
        }
    }

    NSString *rawInput = number.rawInput;
    // If no digit is inserted/removed/modified as a result of our formatting, we
    // return the formatted phone number; otherwise we return the raw input the
    // user entered.
    if (formattedNumber != nil && rawInput.length > 0)
    {
        NSString *normalizedFormattedNumber = [self normalizeHelper:formattedNumber normalizationReplacements:_DIALLABLE_CHAR_MAPPINGS_ removeNonMatches:YES];
        /** @type {string} */
        NSString *normalizedRawInput =[self normalizeHelper:rawInput normalizationReplacements:_DIALLABLE_CHAR_MAPPINGS_ removeNonMatches:YES];

        if (normalizedFormattedNumber != normalizedRawInput)
        {
            formattedNumber = rawInput;
        }
    }
    return formattedNumber;
}


/**
 * Check if rawInput, which is assumed to be in the national format, has a
 * national prefix. The national prefix is assumed to be in digits-only form.
 * @param {string} rawInput
 * @param {string} nationalPrefix
 * @param {string} regionCode
 * @return {boolean}
 * @private
 */
- (BOOL)rawInputContainsNationalPrefix:(NSString*)rawInput nationalPrefix:(NSString*)nationalPrefix regionCode:(NSString*)regionCode
{
    NSString *normalizedNationalNumber = [self normalizeDigitsOnly:rawInput];
    if ([self isStartingStringByRegex:normalizedNationalNumber regex:nationalPrefix])
    {
        @try {
            // Some Japanese numbers (e.g. 00777123) might be mistaken to contain the
            // national prefix when written without it (e.g. 0777123) if we just do
            // prefix matching. To tackle that, we check the validity of the number if
            // the assumed national prefix is removed (777123 won't be valid in
            // Japan).
            NSString *subString = [normalizedNationalNumber substringToIndex:nationalPrefix.length];
            return [self isValidNumber:[self parse:subString defaultRegion:regionCode]];
        }
        @catch (NSException *ex) {
            return NO;
        }
    }
    return NO;
}


/**
 * Returns NO if a number is from a region whose national significant number
 * couldn't contain a leading zero, but has the italian_leading_zero field set
 * to NO.
 * @param {i18n.phonenumbers.PhoneNumber} number
 * @return {boolean}
 * @private
 */
- (BOOL)hasUnexpectedItalianLeadingZero:(NBPhoneNumber*)number
{    
    return number.italianLeadingZero && [self isLeadingZeroPossible:number.countryCode] == NO;
}


/**
 * @param {i18n.phonenumbers.PhoneNumber} number
 * @return {boolean}
 * @private
 */
- (BOOL)hasFormattingPatternForNumber:(NBPhoneNumber*)number
{
    NSString *countryCallingCode = number.countryCode;
    NSString *phoneNumberRegion = [self getRegionCodeForCountryCode:countryCallingCode];
    NBPhoneMetaData *metadata = [self getMetadataForRegionOrCallingCode:countryCallingCode regionCode:phoneNumberRegion];
    
    if (metadata == nil)
    {
        return NO;
    }

    NSString *nationalNumber = [self getNationalSignificantNumber:number];
    NBNumberFormat *formatRule = [self chooseFormattingPatternForNumber:metadata.numberFormats nationalNumber:nationalNumber];
    return formatRule != nil;
}


/**
 * Formats a phone number for out-of-country dialing purposes.
 *
 * Note that in this version, if the number was entered originally using alpha
 * characters and this version of the number is stored in raw_input, this
 * representation of the number will be used rather than the digit
 * representation. Grouping information, as specified by characters such as '-'
 * and ' ', will be retained.
 *
 * <p><b>Caveats:</b></p>
 * <ul>
 * <li>This will not produce good results if the country calling code is both
 * present in the raw input _and_ is the start of the national number. This is
 * not a problem in the regions which typically use alpha numbers.
 * <li>This will also not produce good results if the raw input has any grouping
 * information within the first three digits of the national number, and if the
 * function needs to strip preceding digits/words in the raw input before these
 * digits. Normally people group the first three digits together so this is not
 * a huge problem - and will be fixed if it proves to be so.
 * </ul>
 *
 * @param {i18n.phonenumbers.PhoneNumber} number the phone number that needs to
 *     be formatted.
 * @param {string} regionCallingFrom the region where the call is being placed.
 * @return {string} the formatted phone number.
 */
- (NSString*)formatOutOfCountryKeepingAlphaChars:(NBPhoneNumber*)number regionCallingFrom:(NSString*)regionCallingFrom
{
    NSString *rawInput = number.rawInput;
    // If there is no raw input, then we can't keep alpha characters because there
    // aren't any. In this case, we return formatOutOfCountryCallingNumber.
    if (rawInput.length == 0)
    {
        return [self formatOutOfCountryCallingNumber:number regionCallingFrom:regionCallingFrom];
    }

    NSString *countryCode = number.countryCode;
    if ([self hasValidCountryCallingCode:countryCode] == NO)
    {
        return rawInput;
    }
    // Strip any prefix such as country calling code, IDD, that was present. We do
    // this by comparing the number in raw_input with the parsed number. To do
    // this, first we normalize punctuation. We retain number grouping symbols
    // such as ' ' only.
    rawInput = [self normalizeHelper:rawInput normalizationReplacements:_ALL_PLUS_NUMBER_GROUPING_SYMBOLS_ removeNonMatches:NO];
    // Now we trim everything before the first three digits in the parsed number.
    // We choose three because all valid alpha numbers have 3 digits at the start
    // - if it does not, then we don't trim anything at all. Similarly, if the
    // national number was less than three digits, we don't trim anything at all.
    NSString *nationalNumber = [self getNationalSignificantNumber:number];
    if (nationalNumber.length > 3)
    {
        int firstNationalNumberDigit = [self indexOfStringByString:rawInput target:[nationalNumber substringWithRange:NSMakeRange(0, 3)]];
        if (firstNationalNumberDigit != -1)
        {
            rawInput = [rawInput substringToIndex:firstNationalNumberDigit];
        }
    }

    NBPhoneMetaData *metadataForRegionCallingFrom = [self getMetadataForRegion:regionCallingFrom];
    if (countryCode == NANPA_COUNTRY_CODE_)
    {
        if ([self isNANPACountry:regionCallingFrom])
        {
            return [NSString stringWithFormat:@"%@ %@", countryCode, rawInput];
        }
    }
    else if (metadataForRegionCallingFrom != nil && [countryCode isEqualToString:[self getCountryCodeForValidRegion:regionCallingFrom]])
    {
        NBNumberFormat *formattingPattern = [self chooseFormattingPatternForNumber:metadataForRegionCallingFrom.numberFormats
                                                                         nationalNumber:nationalNumber];
        if (formattingPattern == nil)
        {
            // If no pattern above is matched, we format the original input.
            return rawInput;
        }

        NBNumberFormat *newFormat = [formattingPattern copy];
        // The first group is the first group of digits that the user wrote
        // together.
        newFormat.pattern = @"(\\d+)(.*)";
        // Here we just concatenate them back together after the national prefix
        // has been fixed.
        newFormat.format = @"$1$2";
        // Now we format using this pattern instead of the default pattern, but
        // with the national prefix prefixed if necessary.
        // This will not work in the cases where the pattern (and not the leading
        // digits) decide whether a national prefix needs to be used, since we have
        // overridden the pattern to match anything, but that is not the case in the
        // metadata to date.
        return [self formatNsnUsingPattern:rawInput formattingPattern:newFormat numberFormat:NATIONAL carrierCode:nil];
    }

    NSString *internationalPrefixForFormatting = @"";
    // If an unsupported region-calling-from is entered, or a country with
    // multiple international prefixes, the international format of the number is
    // returned, unless there is a preferred international prefix.
    if (metadataForRegionCallingFrom != nil)
    {
        NSString *internationalPrefix = metadataForRegionCallingFrom.internationalPrefix;
        internationalPrefixForFormatting =
            [self matchesEntirely:UNIQUE_INTERNATIONAL_PREFIX_ string:internationalPrefix] ? internationalPrefix : metadataForRegionCallingFrom.internationalPrefix;
    }

    NSString *regionCode = [self getRegionCodeForCountryCode:countryCode];
    // Metadata cannot be nil because the country calling code is valid.
    NBPhoneMetaData *metadataForRegion = [self getMetadataForRegionOrCallingCode:countryCode regionCode:regionCode];
    NSString *formattedExtension = [self maybeGetFormattedExtension:number metadata:metadataForRegion numberFormat:INTERNATIONAL];
    if (internationalPrefixForFormatting.length > 0)
    {
        return [NSString stringWithFormat:@"%@ %@ %@%@", internationalPrefixForFormatting, countryCode, rawInput, formattedExtension];
    }
    else
    {
        // Invalid region entered as country-calling-from (so no metadata was found
        // for it) or the region chosen has multiple international dialling
        // prefixes.
        return [self prefixNumberWithCountryCallingCode:countryCode phoneNumberFormat:INTERNATIONAL formattedNationalNumber:rawInput formattedExtension:formattedExtension];
    }
}


/**
 * Note in some regions, the national number can be written in two completely
 * different ways depending on whether it forms part of the NATIONAL format or
 * INTERNATIONAL format. The numberFormat parameter here is used to specify
 * which format to use for those cases. If a carrierCode is specified, this will
 * be inserted into the formatted string to replace $CC.
 *
 * @param {string} number a string of characters representing a phone number.
 * @param {i18n.phonenumbers.PhoneMetadata} metadata the metadata for the
 *     region that we think this number is from.
 * @param {i18n.phonenumbers.PhoneNumberFormat} numberFormat the format the
 *     phone number should be formatted into.
 * @param {string=} opt_carrierCode
 * @return {string} the formatted phone number.
 * @private
 */
- (NSString*)formatNsn:(NSString*)phoneNumber metadata:(NBPhoneMetaData*)metadata phoneNumberFormat:(NBEPhoneNumberFormat)numberFormat carrierCode:(NSString*)opt_carrierCode
{
    NSMutableArray *intlNumberFormats = [[NSMutableArray alloc] init];
    for (NBNumberFormat *nf in metadata.numberFormats)
    {
        if (nf.intlFormat != nil)
        {
            [intlNumberFormats addObject:nf];
        }
    }
    // When the intlNumberFormats exists, we use that to format national number
    // for the INTERNATIONAL format instead of using the numberDesc.numberFormats.
    NSArray *availableFormats = ([intlNumberFormats count] <= 0 || numberFormat == NATIONAL) ? metadata.numberFormats : intlNumberFormats;
    NBNumberFormat *formattingPattern = [self chooseFormattingPatternForNumber:availableFormats nationalNumber:phoneNumber];
    return (formattingPattern == nil) ? phoneNumber : [self formatNsnUsingPattern:phoneNumber formattingPattern:formattingPattern numberFormat:numberFormat carrierCode:opt_carrierCode];
}


/**
 * @param {Array.<i18n.phonenumbers.NumberFormat>} availableFormats the
 *     available formats the phone number could be formatted into.
 * @param {string} nationalNumber a string of characters representing a phone
 *     number.
 * @return {i18n.phonenumbers.NumberFormat}
 * @private
 */
- (NBNumberFormat*)chooseFormattingPatternForNumber:(NSArray*)availableFormats nationalNumber:(NSString*)nationalNumber
{
    for (NBNumberFormat *numFormat in availableFormats)
    {
        int size = [numFormat.leadingDigitsPattern count];
        // We always use the last leading_digits_pattern, as it is the most detailed.
        if (size == 0 || [self stringPositionByRegex:nationalNumber regex:[numFormat.leadingDigitsPattern lastObject]])
        {
            if ([self matchesEntirely:numFormat.pattern string:nationalNumber])
            {
                return numFormat;
            }
        }
    }
    return nil;
}


/**
 * Note that carrierCode is optional - if nil or an empty string, no carrier
 * code replacement will take place.
 *
 * @param {string} nationalNumber a string of characters representing a phone
 *     number.
 * @param {i18n.phonenumbers.NumberFormat} formattingPattern the formatting rule
 *     the phone number should be formatted into.
 * @param {i18n.phonenumbers.PhoneNumberFormat} numberFormat the format the
 *     phone number should be formatted into.
 * @param {string=} opt_carrierCode
 * @return {string} the formatted phone number.
 * @private
 */
- (NSString*)formatNsnUsingPattern:(NSString*)nationalNumber formattingPattern:(NBNumberFormat*)formattingPattern numberFormat:(NBEPhoneNumberFormat)numberFormat carrierCode:(NSString*)opt_carrierCode
{
    NSString *numberFormatRule = formattingPattern.format;
    NSString *domesticCarrierCodeFormattingRule = formattingPattern.domesticCarrierCodeFormattingRule;
    NSString *formattedNationalNumber = @"";
    
    NSError *error = nil;
    NSRegularExpression *currentPattern = [NSRegularExpression regularExpressionWithPattern:formattingPattern.pattern
                                                                                    options:0 error:&error];
    
    NSArray *matches = [currentPattern matchesInString:nationalNumber options:0 range:NSMakeRange(0, nationalNumber.length)];
    
    int foundPosition = 0;
    
    for(NSTextCheckingResult *match in matches)
    {
        foundPosition = match.range.location;
        if (foundPosition > 0)
        {
            break;
        }
    }
    
    if (numberFormat == NATIONAL && [self hasValue:opt_carrierCode] && [self hasValue:domesticCarrierCodeFormattingRule])
    {
        NSString *carrierCodeFormattingRule = [self replaceStringByRegex:domesticCarrierCodeFormattingRule regex:CC_PATTERN_ withTemplate:opt_carrierCode];
        
        // Now replace the $FG in the formatting rule with the first group and
        // the carrier code combined in the appropriate way.
        numberFormatRule = [self replaceStringByRegex:numberFormatRule regex:FIRST_GROUP_PATTERN_ withTemplate:carrierCodeFormattingRule];
        formattedNationalNumber = [self replaceStringByRegex:nationalNumber regex:formattingPattern.pattern withTemplate:numberFormatRule];
    }
    else
    {
        // Use the national prefix formatting rule instead.
        NSString *nationalPrefixFormattingRule = formattingPattern.nationalPrefixFormattingRule;
        if (numberFormat == NATIONAL && [self hasValue:nationalPrefixFormattingRule])
        {
            NSString *toTemplate = [self replaceStringByRegex:numberFormatRule regex:FIRST_GROUP_PATTERN_ withTemplate:nationalPrefixFormattingRule];
            formattedNationalNumber = [self replaceStringByRegex:nationalNumber regex:formattingPattern.pattern withTemplate:toTemplate];
        }
        else
        {
            formattedNationalNumber = [self replaceStringByRegex:nationalNumber regex:formattingPattern.pattern withTemplate:numberFormatRule];
        }
    }
    
    if (numberFormat == RFC3966) {
        // Strip any leading punctuation.
        formattedNationalNumber = [self replaceStringByRegex:formattedNationalNumber
                                                       regex:[NSString stringWithFormat:@"^%@", SEPARATOR_PATTERN_] withTemplate:@""];
        // Replace the rest with a dash between each number group.
        formattedNationalNumber = [self replaceStringByRegex:formattedNationalNumber regex:SEPARATOR_PATTERN_ withTemplate:@"-"];
    }
    return formattedNationalNumber;
}


/**
 * Gets a valid number for the specified region.
 *
 * @param {string} regionCode the region for which an example number is needed.
 * @return {i18n.phonenumbers.PhoneNumber} a valid fixed-line number for the
 *     specified region. Returns nil when the metadata does not contain such
 *     information, or the region 001 is passed in. For 001 (representing non-
 *     geographical numbers), call {@link #getExampleNumberForNonGeoEntity}
 *     instead.
 */
- (NBPhoneNumber*)getExampleNumber:(NSString*)regionCode
{
    return [self getExampleNumberForType:regionCode type:FIXED_LINE];
}


/**
 * Gets a valid number for the specified region and number type.
 *
 * @param {string} regionCode the region for which an example number is needed.
 * @param {i18n.phonenumbers.PhoneNumberType} type the type of number that is
 *     needed.
 * @return {i18n.phonenumbers.PhoneNumber} a valid number for the specified
 *     region and type. Returns nil when the metadata does not contain such
 *     information or if an invalid region or region 001 was entered.
 *     For 001 (representing non-geographical numbers), call
 *     {@link #getExampleNumberForNonGeoEntity} instead.
 */
- (NBPhoneNumber*)getExampleNumberForType:(NSString*)regionCode type:(NBEPhoneNumberType)type
{
    // Check the region code is valid.
    if ([self isValidRegionCode:regionCode] == NO)
    {
        return nil;
    }

    NBPhoneNumberDesc *desc = [self getNumberDescByType:[self getMetadataForRegion:regionCode] type:type];
    
    @try {
        if ([self hasValue:desc.exampleNumber ])
        {
            return [self parse:desc.exampleNumber defaultRegion:regionCode];
        }
    }
    @catch (NSException *e)
    {
    }
    
    return nil;
}


/**
 * Gets a valid number for the specified country calling code for a
 * non-geographical entity.
 *
 * @param {number} countryCallingCode the country calling code for a
 *     non-geographical entity.
 * @return {i18n.phonenumbers.PhoneNumber} a valid number for the
 *     non-geographical entity. Returns nil when the metadata does not contain
 *     such information, or the country calling code passed in does not belong
 *     to a non-geographical entity.
 */
- (NBPhoneNumber*)getExampleNumberForNonGeoEntity:(NSString*)countryCallingCode
{
    NBPhoneMetaData *metadata = [self getMetadataForNonGeographicalRegion:countryCallingCode];
    
    if (metadata != nil)
    {
        NBPhoneNumberDesc *desc = metadata.generalDesc;
        @try {
            if ([self hasValue:desc.exampleNumber])
            {
                NSString *callCode = [NSString stringWithFormat:@"+%@%@", countryCallingCode, desc.exampleNumber];
                return [self parse:callCode defaultRegion:UNKNOWN_REGION_];
            }
        }
        @catch (NSException *e) {
        }
    }
    return nil;
}


/**
 * Gets the formatted extension of a phone number, if the phone number had an
 * extension specified. If not, it returns an empty string.
 *
 * @param {i18n.phonenumbers.PhoneNumber} number the PhoneNumber that might have
 *     an extension.
 * @param {i18n.phonenumbers.PhoneMetadata} metadata the metadata for the
 *     region that we think this number is from.
 * @param {i18n.phonenumbers.PhoneNumberFormat} numberFormat the format the
 *     phone number should be formatted into.
 * @return {string} the formatted extension if any.
 * @private
 */
- (NSString*)maybeGetFormattedExtension:(NBPhoneNumber*)number metadata:(NBPhoneMetaData*)metadata numberFormat:(NBEPhoneNumberFormat)numberFormat
{
    if ([self hasValue:number.extension] == NO)
    {
        return @"";
    }
    else
    {
        if (numberFormat == RFC3966)
        {
            return [NSString stringWithFormat:@"%@%@", RFC3966_EXTN_PREFIX_, number.extension];
        }
        else
        {
            if ([self hasValue:metadata.preferredExtnPrefix])
            {
                return [NSString stringWithFormat:@"%@%@", metadata.preferredExtnPrefix, number.extension];
            }
            else
            {
                return [NSString stringWithFormat:@"%@%@", DEFAULT_EXTN_PREFIX_, number.extension];
            }
        }
    }
}


/**
 * @param {i18n.phonenumbers.PhoneMetadata} metadata
 * @param {i18n.phonenumbers.PhoneNumberType} type
 * @return {i18n.phonenumbers.PhoneNumberDesc}
 * @private
 */
- (NBPhoneNumberDesc*)getNumberDescByType:(NBPhoneMetaData*)metadata type:(NBEPhoneNumberType)type
{
    switch (type)
    {
        case PREMIUM_RATE:
            return metadata.premiumRate;
        case TOLL_FREE:
            return metadata.tollFree;
        case MOBILE:
            return metadata.mobile;
        case FIXED_LINE:
        case FIXED_LINE_OR_MOBILE:
            return metadata.fixedLine;
        case SHARED_COST:
            return metadata.sharedCost;
        case VOIP:
            return metadata.voip;
        case PERSONAL_NUMBER:
            return metadata.personalNumber;
        case PAGER:
            return metadata.pager;
        case UAN:
            return metadata.uan;
        case VOICEMAIL:
            return metadata.voicemail;
        default:
            return metadata.generalDesc;
    }
}

/**
 * Gets the type of a phone number.
 *
 * @param {i18n.phonenumbers.PhoneNumber} number the phone number that we want
 *     to know the type.
 * @return {i18n.phonenumbers.PhoneNumberType} the type of the phone number.
 */
- (NBEPhoneNumberType)getNumberType:(NBPhoneNumber*)phoneNumber
{
    NSString *regionCode = [self getRegionCodeForNumber:phoneNumber];
    NBPhoneMetaData *metadata = [self getMetadataForRegionOrCallingCode:phoneNumber.countryCode regionCode:regionCode];
    if (metadata == nil)
    {
        return UNKNOWN;
    }
    
    NSString *nationalSignificantNumber = [self getNationalSignificantNumber:phoneNumber];
    return [self getNumberTypeHelper:nationalSignificantNumber metadata:metadata];
}


/**
 * @param {string} nationalNumber
 * @param {i18n.phonenumbers.PhoneMetadata} metadata
 * @return {i18n.phonenumbers.PhoneNumberType}
 * @private
 */
- (NBEPhoneNumberType)getNumberTypeHelper:(NSString*)nationalNumber metadata:(NBPhoneMetaData*)metadata
{
    NBPhoneNumberDesc *generalNumberDesc = metadata.generalDesc;
    
    if ([self hasValue:generalNumberDesc.nationalNumberPattern] == NO ||
        [self isNumberMatchingDesc:nationalNumber numberDesc:generalNumberDesc] == NO)
    {
        return UNKNOWN;
    }
    
    if ([self isNumberMatchingDesc:nationalNumber numberDesc:metadata.premiumRate])
    {
        return PREMIUM_RATE;
    }
    
    if ([self isNumberMatchingDesc:nationalNumber numberDesc:metadata.tollFree])
    {
        return TOLL_FREE;
    }
    
    if ([self isNumberMatchingDesc:nationalNumber numberDesc:metadata.sharedCost])
    {
        return SHARED_COST;
    }
    
    if ([self isNumberMatchingDesc:nationalNumber numberDesc:metadata.voip])
    {
        return VOIP;
    }
    
    if ([self isNumberMatchingDesc:nationalNumber numberDesc:metadata.personalNumber])
    {
        return PERSONAL_NUMBER;
    }
    
    if ([self isNumberMatchingDesc:nationalNumber numberDesc:metadata.pager]) {
        return PAGER;
    }
    
    if ([self isNumberMatchingDesc:nationalNumber numberDesc:metadata.uan]) {
        return UAN;
    }
    
    if ([self isNumberMatchingDesc:nationalNumber numberDesc:metadata.voicemail]) {
        return VOICEMAIL;
    }
    
    if ([self isNumberMatchingDesc:nationalNumber numberDesc:metadata.fixedLine])
    {
        if (metadata.sameMobileAndFixedLinePattern)
        {
            return FIXED_LINE_OR_MOBILE;
        }
        else if ([self isNumberMatchingDesc:nationalNumber numberDesc:metadata.mobile])
        {
            return FIXED_LINE_OR_MOBILE;
        }
        return FIXED_LINE;
    }
    
    // Otherwise, test to see if the number is mobile. Only do this if certain
    // that the patterns for mobile and fixed line aren't the same.
    if ([metadata.sameMobileAndFixedLinePattern boolValue] == NO && [self isNumberMatchingDesc:nationalNumber numberDesc:metadata.mobile])
    {
        return MOBILE;
    }
    
    return UNKNOWN;
}


/**
 * Returns the metadata for the given region code or {@code nil} if the region
 * code is invalid or unknown.
 *
 * @param {?string} regionCode
 * @return {i18n.phonenumbers.PhoneMetadata}
 */
- (NBPhoneMetaData*)getMetadataForRegion:(NSString*)regionCode
{
    if ([self hasValue:regionCode] == NO)
    {
        return nil;
    }
    
    regionCode = [regionCode uppercaseString];
    
    NBPhoneMetaData *metadata = [self.coreMetaData objectForKey:regionCode];
    if (metadata == nil)
    {
        return nil;
    }
    return metadata;
}


/**
 * @param {number} countryCallingCode
 * @return {i18n.phonenumbers.PhoneMetadata}
 */
- (NBPhoneMetaData*)getMetadataForNonGeographicalRegion:(NSString*)countryCallingCode
{
    return [self getMetadataForRegion:countryCallingCode];
}


/**
 * @param {string} nationalNumber
 * @param {i18n.phonenumbers.PhoneNumberDesc} numberDesc
 * @return {boolean}
 * @private
 */
- (BOOL)isNumberMatchingDesc:(NSString*)nationalNumber numberDesc:(NBPhoneNumberDesc*)numberDesc
{
    return [self matchesEntirely:numberDesc.possibleNumberPattern string:nationalNumber] &&
    [self matchesEntirely:numberDesc.nationalNumberPattern string:nationalNumber];
}


/**
 * Tests whether a phone number matches a valid pattern. Note this doesn't
 * verify the number is actually in use, which is impossible to tell by just
 * looking at a number itself.
 *
 * @param {i18n.phonenumbers.PhoneNumber} number the phone number that we want
 *     to validate.
 * @return {boolean} a boolean that indicates whether the number is of a valid
 *     pattern.
 */
- (BOOL)isValidNumber:(NBPhoneNumber*)number
{
    NSString *regionCode = [self getRegionCodeForNumber:number];
    return [self isValidNumberForRegion:number regionCode:regionCode];
}


/**
 * Tests whether a phone number is valid for a certain region. Note this doesn't
 * verify the number is actually in use, which is impossible to tell by just
 * looking at a number itself. If the country calling code is not the same as
 * the country calling code for the region, this immediately exits with NO.
 * After this, the specific number pattern rules for the region are examined.
 * This is useful for determining for example whether a particular number is
 * valid for Canada, rather than just a valid NANPA number.
 * Warning: In most cases, you want to use {@link #isValidNumber} instead. For
 * example, this method will mark numbers from British Crown dependencies such
 * as the Isle of Man as invalid for the region "GB" (United Kingdom), since it
 * has its own region code, "IM", which may be undesirable.
 *
 * @param {i18n.phonenumbers.PhoneNumber} number the phone number that we want
 *     to validate.
 * @param {?string} regionCode the region that we want to validate the phone
 *     number for.
 * @return {boolean} a boolean that indicates whether the number is of a valid
 *     pattern.
 */
- (BOOL)isValidNumberForRegion:(NBPhoneNumber*)number regionCode:(NSString*)regionCode
{
    NSString *countryCode = number.countryCode;
    NBPhoneMetaData *metadata = [self getMetadataForRegionOrCallingCode:countryCode regionCode:regionCode];
    if (metadata == nil ||
        ([REGION_CODE_FOR_NON_GEO_ENTITY isEqualToString:regionCode] == NO &&
         [countryCode isEqualToString:[self getCountryCodeForValidRegion:regionCode]] == NO))
    {
            // Either the region code was invalid, or the country calling code for this
            // number does not match that of the region code.
            return NO;
    }
    
    NBPhoneNumberDesc *generalNumDesc = metadata.generalDesc;
    NSString *nationalSignificantNumber = [self getNationalSignificantNumber:number];
    
    // For regions where we don't have metadata for PhoneNumberDesc, we treat any
    // number passed in as a valid number if its national significant number is
    // between the minimum and maximum lengths defined by ITU for a national
    // significant number.
    if ([self hasValue:generalNumDesc.nationalNumberPattern] == NO)
    {
        int numberLength = nationalSignificantNumber.length;
        return numberLength > MIN_LENGTH_FOR_NSN_ && numberLength <= MAX_LENGTH_FOR_NSN_;
    }
    
    return [self getNumberTypeHelper:nationalSignificantNumber metadata:metadata] != UNKNOWN;
}


/**
 * Returns the region where a phone number is from. This could be used for
 * geocoding at the region level.
 *
 * @param {i18n.phonenumbers.PhoneNumber} number the phone number whose origin
 *     we want to know.
 * @return {?string} the region where the phone number is from, or nil
 *     if no region matches this calling code.
 */
- (NSString*)getRegionCodeForNumber:(NBPhoneNumber*)phoneNumber
{
    if (phoneNumber == nil)
    {
        return nil;
    }
    
    NSArray *regionCodes = [self regionCodeFromCountryCode:phoneNumber.countryCode];
    if (regionCodes == nil || [regionCodes count] <= 0)
    {
        return nil;
    }
    
    if ([regionCodes count] == 1)
    {
        return [regionCodes objectAtIndex:0];
    }
    else
    {
        return [self getRegionCodeForNumberFromRegionList:phoneNumber regionCodes:regionCodes];
    }
}


/**
 * @param {i18n.phonenumbers.PhoneNumber} number
 * @param {Array.<string>} regionCodes
 * @return {?string}
 * @private
 */
- (NSString*)getRegionCodeForNumberFromRegionList:(NBPhoneNumber*)phoneNumber regionCodes:(NSArray*)regionCodes
{
    NSString *nationalNumber = [self getNationalSignificantNumber:phoneNumber];
    int regionCodesCount = [regionCodes count];
    
    for (int i = 0; i<regionCodesCount; i++)
    {
        NSString *regionCode = [regionCodes objectAtIndex:i];
        NBPhoneMetaData *metadata = [self getMetadataForRegion:regionCode];
        
        if ([self hasValue:metadata.leadingDigits])
        {
            if ([self stringPositionByRegex:nationalNumber regex:metadata.leadingDigits] == 0)
            {
                return regionCode;
            }
        }
        else if ([self getNumberTypeHelper:nationalNumber metadata:metadata] != UNKNOWN)
        {
            return regionCode;
        }
    }
    return nil;
}


/**
 * Returns the region code that matches the specific country calling code. In
 * the case of no region code being found, ZZ will be returned. In the case of
 * multiple regions, the one designated in the metadata as the 'main' region for
 * this calling code will be returned.
 *
 * @param {number} countryCallingCode the country calling code.
 * @return {string}
 */
- (NSString*)getRegionCodeForCountryCode:(NSString*)countryCallingCode
{
    NSArray *regionCodes = [self regionCodeFromCountryCode:countryCallingCode];
    return regionCodes == nil ? UNKNOWN_REGION_ : regionCodes[0];
}


/**
 * Returns a list with the region codes that match the specific country calling
 * code. For non-geographical country calling codes, the region code 001 is
 * returned. Also, in the case of no region code being found, an empty list is
 * returned.
 *
 * @param {number} countryCallingCode the country calling code.
 * @return {Array.<string>}
 */
- (NSArray*)getRegionCodesForCountryCode:(NSString*)countryCallingCode
{
    NSArray *regionCodes = [self regionCodeFromCountryCode:countryCallingCode];
    return regionCodes == nil ? nil : regionCodes;
}


/**
 * Returns the country calling code for a specific region. For example, this
 * would be 1 for the United States, and 64 for New Zealand.
 *
 * @param {?string} regionCode the region that we want to get the country
 *     calling code for.
 * @return {number} the country calling code for the region denoted by
 *     regionCode.
 */
- (NSString*)getCountryCodeForRegion:(NSString*)regionCode
{
    if ([self isValidRegionCode:regionCode] == NO)
    {
        return nil;
    }
    return [self getCountryCodeForValidRegion:regionCode];
}


/**
 * Returns the country calling code for a specific region. For example, this
 * would be 1 for the United States, and 64 for New Zealand. Assumes the region
 * is already valid.
 *
 * @param {?string} regionCode the region that we want to get the country
 *     calling code for.
 * @return {number} the country calling code for the region denoted by
 *     regionCode.
 * @throws {string} if the region is invalid
 * @private
 */
- (NSString*)getCountryCodeForValidRegion:(NSString*)regionCode
{
    NBPhoneMetaData *metadata = [self getMetadataForRegion:regionCode];
    if (metadata == nil)
    {
        NSException* metaException = [NSException exceptionWithName:@"FileNotFoundException"
                                                             reason:[NSString stringWithFormat:@"Invalid region code:%@", regionCode]
                                                           userInfo:nil];
        @throw metaException;
    }
    return metadata.countryCode;
}


/**
 * Returns the national dialling prefix for a specific region. For example, this
 * would be 1 for the United States, and 0 for New Zealand. Set stripNonDigits
 * to NO to strip symbols like '~' (which indicates a wait for a dialling
 * tone) from the prefix returned. If no national prefix is present, we return
 * nil.
 *
 * <p>Warning: Do not use this method for do-your-own formatting - for some
 * regions, the national dialling prefix is used only for certain types of
 * numbers. Use the library's formatting functions to prefix the national prefix
 * when required.
 *
 * @param {?string} regionCode the region that we want to get the dialling
 *     prefix for.
 * @param {boolean} stripNonDigits NO to strip non-digits from the national
 *     dialling prefix.
 * @return {?string} the dialling prefix for the region denoted by
 *     regionCode.
 */
- (NSString*)getNddPrefixForRegion:(NSString*)regionCode stripNonDigits:(BOOL)stripNonDigits
{
    NBPhoneMetaData *metadata = [self getMetadataForRegion:regionCode ];
    if (metadata == nil)
    {
        return nil;
    }

    NSString *nationalPrefix = metadata.nationalPrefix;
    // If no national prefix was found, we return nil.
    if (nationalPrefix.length == 0)
    {
        return nil;
    }
    
    if (stripNonDigits)
    {
        // Note: if any other non-numeric symbols are ever used in national
        // prefixes, these would have to be removed here as well.
        nationalPrefix = [nationalPrefix stringByReplacingOccurrencesOfString:@"~" withString:@""];
    }
    return nationalPrefix;
}


/**
 * Checks if this is a region under the North American Numbering Plan
 * Administration (NANPA).
 *
 * @param {?string} regionCode the ISO 3166-1 two-letter region code.
 * @return {boolean} NO if regionCode is one of the regions under NANPA.
 */
- (BOOL)isNANPACountry:(NSString*)regionCode
{
    BOOL isExists = NO;
    
    NSArray *res = [self regionCodeFromCountryCode:NANPA_COUNTRY_CODE_];
    for (NSString *inRegionCode in res)
    {
        if ([inRegionCode isEqualToString:regionCode.uppercaseString])
        {
            isExists = YES;
        }
    }
    
    return regionCode != nil && isExists;
}


/**
 * Checks whether countryCode represents the country calling code from a region
 * whose national significant number could contain a leading zero. An example of
 * such a region is Italy. Returns NO if no metadata for the country is
 * found.
 *
 * @param {number} countryCallingCode the country calling code.
 * @return {boolean}
 */
- (BOOL)isLeadingZeroPossible:(NSString*)countryCallingCode
{
    NBPhoneMetaData *mainMetadataForCallingCode = [self getMetadataForRegionOrCallingCode:countryCallingCode
                                                                               regionCode:[self getRegionCodeForCountryCode:countryCallingCode]];
    
    return mainMetadataForCallingCode != nil && [mainMetadataForCallingCode.leadingZeroPossible boolValue];
}


/**
 * Checks if the number is a valid vanity (alpha) number such as 800 MICROSOFT.
 * A valid vanity number will start with at least 3 digits and will have three
 * or more alpha characters. This does not do region-specific checks - to work
 * out if this number is actually valid for a region, it should be parsed and
 * methods such as {@link #isPossibleNumberWithReason} and
 * {@link #isValidNumber} should be used.
 *
 * @param {string} number the number that needs to be checked.
 * @return {boolean} NO if the number is a valid vanity number.
 */
- (BOOL)isAlphaNumber:(NSString*)number
{
    if ([self isViablePhoneNumber:number] == NO)
    {
        // Number is too short, or doesn't match the basic phone number pattern.
        return NO;
    }
    
    /** @type {!goog.string.StringBuffer} */
    NSString *strippedNumber = [self maybeStripExtension:number];
    
    return [self matchesEntirely:VALID_ALPHA_PHONE_PATTERN_ string:strippedNumber];
}


/**
 * Convenience wrapper around {@link #isPossibleNumberWithReason}. Instead of
 * returning the reason for failure, this method returns a boolean value.
 *
 * @param {i18n.phonenumbers.PhoneNumber} number the number that needs to be
 *     checked.
 * @return {boolean} NO if the number is possible.
 */
- (BOOL)isPossibleNumber:(NBPhoneNumber*)number
{    
    return [self isPossibleNumberWithReason:number] == IS_POSSIBLE;
}


/**
 * Helper method to check a number against a particular pattern and determine
 * whether it matches, or is too short or too long. Currently, if a number
 * pattern suggests that numbers of length 7 and 10 are possible, and a number
 * in between these possible lengths is entered, such as of length 8, this will
 * return TOO_LONG.
 *
 * @param {string} numberPattern
 * @param {string} number
 * @return {ValidationResult}
 * @private
 */
- (NBEValidationResult)testNumberLengthAgainstPattern:(NSString*)numberPattern number:(NSString*)number
{
    if ([self matchesEntirely:numberPattern string:number])
    {
        return IS_POSSIBLE;
    }
        
    if ([self stringPositionByRegex:number regex:numberPattern] == 0)
    {
        return TOO_LONG;
    }
    else
    {
        return TOO_SHORT;
    }
}


/**
 * Check whether a phone number is a possible number. It provides a more lenient
 * check than {@link #isValidNumber} in the following sense:
 * <ol>
 * <li>It only checks the length of phone numbers. In particular, it doesn't
 * check starting digits of the number.
 * <li>It doesn't attempt to figure out the type of the number, but uses general
 * rules which applies to all types of phone numbers in a region. Therefore, it
 * is much faster than isValidNumber.
 * <li>For fixed line numbers, many regions have the concept of area code, which
 * together with subscriber number constitute the national significant number.
 * It is sometimes okay to dial the subscriber number only when dialing in the
 * same area. This function will return NO if the subscriber-number-only
 * version is passed in. On the other hand, because isValidNumber validates
 * using information on both starting digits (for fixed line numbers, that would
 * most likely be area codes) and length (obviously includes the length of area
 * codes for fixed line numbers), it will return NO for the
 * subscriber-number-only version.
 * </ol>
 *
 * @param {i18n.phonenumbers.PhoneNumber} number the number that needs to be
 *     checked.
 * @return {ValidationResult} a
 *     ValidationResult object which indicates whether the number is possible.
 */
- (NBEValidationResult)isPossibleNumberWithReason:(NBPhoneNumber*)number
{
    NSString *nationalNumber = [self getNationalSignificantNumber:number];
    NSString *countryCode = number.countryCode;
    // Note: For Russian Fed and NANPA numbers, we just use the rules from the
    // default region (US or Russia) since the getRegionCodeForNumber will not
    // work if the number is possible but not valid. This would need to be
    // revisited if the possible number pattern ever differed between various
    // regions within those plans.
    if ([self hasValidCountryCallingCode:countryCode] == NO)
    {
        return INVALID_COUNTRY_CODE;
    }
    
    NSString *regionCode = [self getRegionCodeForCountryCode:countryCode];
    // Metadata cannot be nil because the country calling code is valid.
    NBPhoneMetaData *metadata = [self getMetadataForRegionOrCallingCode:countryCode regionCode:regionCode];
    NBPhoneNumberDesc *generalNumDesc = metadata.generalDesc;
    
    // Handling case of numbers with no metadata.
    if ([self hasValue:generalNumDesc.nationalNumberPattern] == NO)
    {
        int numberLength = nationalNumber.length;
        
        if (numberLength < MIN_LENGTH_FOR_NSN_)
        {
            return TOO_SHORT;
        }
        else if (numberLength > MAX_LENGTH_FOR_NSN_)
        {
            return TOO_LONG;
        }
        else
        {
            return IS_POSSIBLE;
        }
    }

    NSString *possibleNumberPattern = generalNumDesc.possibleNumberPattern;
    return [self testNumberLengthAgainstPattern:possibleNumberPattern number:nationalNumber];
}


/**
 * Check whether a phone number is a possible number given a number in the form
 * of a string, and the region where the number could be dialed from. It
 * provides a more lenient check than {@link #isValidNumber}. See
 * {@link #isPossibleNumber} for details.
 *
 * <p>This method first parses the number, then invokes
 * {@link #isPossibleNumber} with the resultant PhoneNumber object.
 *
 * @param {string} number the number that needs to be checked, in the form of a
 *     string.
 * @param {string} regionDialingFrom the region that we are expecting the number
 *     to be dialed from.
 *     Note this is different from the region where the number belongs.
 *     For example, the number +1 650 253 0000 is a number that belongs to US.
 *     When written in this form, it can be dialed from any region. When it is
 *     written as 00 1 650 253 0000, it can be dialed from any region which uses
 *     an international dialling prefix of 00. When it is written as
 *     650 253 0000, it can only be dialed from within the US, and when written
 *     as 253 0000, it can only be dialed from within a smaller area in the US
 *     (Mountain View, CA, to be more specific).
 * @return {boolean} NO if the number is possible.
 */
- (BOOL)isPossibleNumberString:(NSString*)number regionDialingFrom:(NSString*)regionDialingFrom
{
    @try {
        return [self isPossibleNumber:[self parse:number defaultRegion:regionDialingFrom]];
    }
    @catch (NSException *e)
    {
        return NO;
    }
}


/**
 * Attempts to extract a valid number from a phone number that is too long to be
 * valid, and resets the PhoneNumber object passed in to that valid version. If
 * no valid number could be extracted, the PhoneNumber object passed in will not
 * be modified.
 * @param {i18n.phonenumbers.PhoneNumber} number a PhoneNumber object which
 *     contains a number that is too long to be valid.
 * @return {boolean} NO if a valid phone number can be successfully extracted.
 */
- (BOOL)truncateTooLongNumber:(NBPhoneNumber*)number
{    
    if ([self isValidNumber:number]) {
        return YES;
    }

    NBPhoneNumber *numberCopy = [number copy];
    /** @type {number} */
    int nationalNumber = [number.nationalNumber intValue];
    do {
        nationalNumber = floor(nationalNumber / 10);
        numberCopy.nationalNumber = [NSString stringWithFormat:@"%d", nationalNumber];
        if (nationalNumber == 0 || [self isPossibleNumberWithReason:numberCopy] == TOO_SHORT)
        {
            return NO;
        }
    }
    while ([self isValidNumber:numberCopy] == NO);
    
    number.nationalNumber = [NSString stringWithFormat:@"%d", nationalNumber];
    return NO;
}


/**
 * Extracts country calling code from fullNumber, returns it and places the
 * remaining number in nationalNumber. It assumes that the leading plus sign or
 * IDD has already been removed. Returns 0 if fullNumber doesn't start with a
 * valid country calling code, and leaves nationalNumber unmodified.
 *
 * @param {!goog.string.StringBuffer} fullNumber
 * @param {!goog.string.StringBuffer} nationalNumber
 * @return {number}
 */
- (NSString*)extractCountryCode:(NSString*)fullNumber nationalNumber:(NSString*)nationalNumber
{
    if ((fullNumber.length == 0) || ([[fullNumber substringToIndex:1] isEqualToString:@"0"]))
    {
        // Country codes do not begin with a '0'.
        return nil;
    }

    NSString *potentialCountryCode = nil;
    int numberLength = fullNumber.length;
    
    for (int i = 1; i <= MAX_LENGTH_COUNTRY_CODE_ && i <= numberLength; ++i)
    {
        potentialCountryCode = [fullNumber substringWithRange:NSMakeRange(0, i)];
        NSArray *regionCodes = [self regionCodeFromCountryCode:potentialCountryCode];
        
        if (regionCodes != nil && regionCodes.count > 0)
        {
            nationalNumber = [NSString stringWithFormat:@"%@%@", nationalNumber, [fullNumber substringToIndex:i]];
            return potentialCountryCode;
        }
    }
    
    return nil;
}


/**
 * Tries to extract a country calling code from a number. This method will
 * return zero if no country calling code is considered to be present. Country
 * calling codes are extracted in the following ways:
 * <ul>
 * <li>by stripping the international dialing prefix of the region the person is
 * dialing from, if this is present in the number, and looking at the next
 * digits
 * <li>by stripping the '+' sign if present and then looking at the next digits
 * <li>by comparing the start of the number and the country calling code of the
 * default region. If the number is not considered possible for the numbering
 * plan of the default region initially, but starts with the country calling
 * code of this region, validation will be reattempted after stripping this
 * country calling code. If this number is considered a possible number, then
 * the first digits will be considered the country calling code and removed as
 * such.
 * </ul>
 *
 * It will throw a i18n.phonenumbers.Error if the number starts with a '+' but
 * the country calling code supplied after this does not match that of any known
 * region.
 *
 * @param {string} number non-normalized telephone number that we wish to
 *     extract a country calling code from - may begin with '+'.
 * @param {i18n.phonenumbers.PhoneMetadata} defaultRegionMetadata metadata
 *     about the region this number may be from.
 * @param {!goog.string.StringBuffer} nationalNumber a string buffer to store
 *     the national significant number in, in the case that a country calling
 *     code was extracted. The number is appended to any existing contents. If
 *     no country calling code was extracted, this will be left unchanged.
 * @param {boolean} keepRawInput NO if the country_code_source and
 *     preferred_carrier_code fields of phoneNumber should be populated.
 * @param {i18n.phonenumbers.PhoneNumber} phoneNumber the PhoneNumber object
 *     where the country_code and country_code_source need to be populated.
 *     Note the country_code is always populated, whereas country_code_source is
 *     only populated when keepCountryCodeSource is NO.
 * @return {number} the country calling code extracted or 0 if none could be
 *     extracted.
 * @throws {i18n.phonenumbers.Error}
 */
- (NSString*)maybeExtractCountryCode:(NSString*)number metadata:(NBPhoneMetaData*)defaultRegionMetadata
                      nationalNumber:(NSString*)nationalNumber keepRawInput:(BOOL)keepRawInput phoneNumber:(NBPhoneNumber*)phoneNumber
{
    if (number.length <= 0)
    {
        return nil;
    }
    
    NSString *fullNumber = [number copy];
    // Set the default prefix to be something that will never match.
    NSString *possibleCountryIddPrefix = nil;
    
    if (defaultRegionMetadata != nil)
    {
        possibleCountryIddPrefix = defaultRegionMetadata.internationalPrefix;
    }
    
    if (possibleCountryIddPrefix == nil)
    {
        possibleCountryIddPrefix = @"NonMatch";
    }
    
    /** @type {CountryCodeSource} */
    NBECountryCodeSource countryCodeSource = [self maybeStripInternationalPrefixAndNormalize:fullNumber possibleIddPrefix:possibleCountryIddPrefix];
    
    if (keepRawInput)
    {
        phoneNumber.countryCodeSource = countryCodeSource;
    }
    
    if (countryCodeSource != FROM_DEFAULT_COUNTRY)
    {
        if (fullNumber.length <= MIN_LENGTH_FOR_NSN_)
        {
            NSException* metaException = [NSException exceptionWithName:TOO_SHORT_AFTER_IDD_STR
                                                                 reason:[NSString stringWithFormat:@"TOO_SHORT_AFTER_IDD %@", fullNumber]
                                                               userInfo:nil];
            @throw metaException;
        }

        NSString *potentialCountryCode = [self extractCountryCode:fullNumber nationalNumber:nationalNumber];
        if (potentialCountryCode != nil)
        {
            phoneNumber.countryCode = potentialCountryCode;
            return potentialCountryCode;
        }
        
        // If this fails, they must be using a strange country calling code that we
        // don't recognize, or that doesn't exist.
        NSException* metaException = [NSException exceptionWithName:INVALID_COUNTRY_CODE_STR
                                                             reason:[NSString stringWithFormat:@"INVALID_COUNTRY_CODE %@", potentialCountryCode]
                                                           userInfo:nil];
        @throw metaException;
    }
    else if (defaultRegionMetadata != nil)
    {
        // Check to see if the number starts with the country calling code for the
        // default region. If so, we remove the country calling code, and do some
        // checks on the validity of the number before and after.
        NSString *defaultCountryCode = defaultRegionMetadata.countryCode;
        NSString *normalizedNumber = [fullNumber copy];
        
        if ([normalizedNumber hasPrefix:defaultCountryCode] && defaultCountryCode.length > 0)
        {
            NSString *potentialNationalNumber = [normalizedNumber substringToIndex:defaultCountryCode.length - 1];
            NBPhoneNumberDesc *generalDesc = defaultRegionMetadata.generalDesc;
            
            NSString *validNumberPattern = generalDesc.nationalNumberPattern;
            // Passing nil since we don't need the carrier code.
            [self maybeStripNationalPrefixAndCarrierCode:potentialNationalNumber metadata:defaultRegionMetadata carrierCode:nil];

            NSString *potentialNationalNumberStr = [potentialNationalNumber copy];

            NSString *possibleNumberPattern = generalDesc.possibleNumberPattern;
            // If the number was not valid before but is valid now, or if it was too
            // long before, we consider the number with the country calling code
            // stripped to be a better result and keep that instead.
            if (([self matchesEntirely:validNumberPattern string:fullNumber] == NO &&
                 [self matchesEntirely:validNumberPattern string:potentialNationalNumberStr]) ||
                [self testNumberLengthAgainstPattern:possibleNumberPattern number:fullNumber] == TOO_LONG)
            {
                nationalNumber = [NSString stringWithFormat:@"%@%@", nationalNumber, potentialNationalNumberStr];
                if (keepRawInput)
                {
                    phoneNumber.countryCodeSource = FROM_NUMBER_WITHOUT_PLUS_SIGN;
                }
                phoneNumber.countryCode = defaultCountryCode;
                return defaultCountryCode;
            }
        }
    }
    // No country calling code present.
    phoneNumber.countryCode = @"0";
    return nil;
}


/**
 * Strips the IDD from the start of the number if present. Helper function used
 * by maybeStripInternationalPrefixAndNormalize.
 *
 * @param {!RegExp} iddPattern the regular expression for the international
 *     prefix.
 * @param {!goog.string.StringBuffer} number the phone number that we wish to
 *     strip any international dialing prefix from.
 * @return {boolean} NO if an international prefix was present.
 * @private
 */
- (BOOL)parsePrefixAsIdd:(NSString*)iddPattern sourceString:(NSString*)number
{    
    NSString *numberStr = [number copy];
    
    if ([self stringPositionByRegex:numberStr regex:iddPattern] == 0)
    {
        NSTextCheckingResult *matched = [[self matchesByRegex:numberStr regex:iddPattern] objectAtIndex:0];
        int matchEnd = matched.range.length;
        NSString *subString = [numberStr substringToIndex:matchEnd];
        
        NSRegularExpression *currentPattern = self.CAPTURING_DIGIT_PATTERN;
        NSArray *matchedGroups = [currentPattern matchesInString:subString options:0 range:NSMakeRange(0, subString.length)];
        
        if (matchedGroups && [matchedGroups count] > 1 &&
            [matchedGroups objectAtIndex:1] != nil && [[matchedGroups objectAtIndex:1] length] > 0)
        {
            NSString *normalizedGroup = [self normalizeDigitsOnly:[matchedGroups objectAtIndex:1]];
            if ([normalizedGroup isEqualToString:@"0"])
            {
                return NO;
            }
        }
        
        number = [NSString stringWithFormat:@"%@", subString];
        return NO;
    }
    return NO;
}


/**
 * Strips any international prefix (such as +, 00, 011) present in the number
 * provided, normalizes the resulting number, and indicates if an international
 * prefix was present.
 *
 * @param {!goog.string.StringBuffer} number the non-normalized telephone number
 *     that we wish to strip any international dialing prefix from.
 * @param {string} possibleIddPrefix the international direct dialing prefix
 *     from the region we think this number may be dialed in.
 * @return {CountryCodeSource} the corresponding
 *     CountryCodeSource if an international dialing prefix could be removed
 *     from the number, otherwise CountryCodeSource.FROM_DEFAULT_COUNTRY if
 *     the number did not seem to be in international format.
 */
- (NBECountryCodeSource)maybeStripInternationalPrefixAndNormalize:(NSString*)numberStr possibleIddPrefix:(NSString*)possibleIddPrefix
{
    if (numberStr.length == 0)
    {
        return FROM_DEFAULT_COUNTRY;
    }
    
    // Check to see if the number begins with one or more plus signs.
    if ([self isStartingStringByRegex:numberStr regex:self.LEADING_PLUS_CHARS_PATTERN_])
    {
        numberStr = [self replaceStringByRegex:numberStr regex:self.LEADING_PLUS_CHARS_PATTERN_ withTemplate:@""];
        // Can now normalize the rest of the number since we've consumed the '+'
        // sign at the start.
        numberStr = [self normalizePhoneNumber:numberStr];
        return FROM_NUMBER_WITH_PLUS_SIGN;
    }
    
    // Attempt to parse the first digits as an international prefix.
    NSString *iddPattern = [possibleIddPrefix copy];
    numberStr = [self normalizePhoneNumber:numberStr];

    return [self parsePrefixAsIdd:iddPattern sourceString:numberStr] ? FROM_NUMBER_WITH_IDD : FROM_DEFAULT_COUNTRY;
}


/**
 * Strips any national prefix (such as 0, 1) present in the number provided.
 *
 * @param {!goog.string.StringBuffer} number the normalized telephone number
 *     that we wish to strip any national dialing prefix from.
 * @param {i18n.phonenumbers.PhoneMetadata} metadata the metadata for the
 *     region that we think this number is from.
 * @param {goog.string.StringBuffer} carrierCode a place to insert the carrier
 *     code if one is extracted.
 * @return {boolean} NO if a national prefix or carrier code (or both) could
 *     be extracted.
 */
- (NSString *)maybeStripNationalPrefixAndCarrierCode:(NSString*)numberStr metadata:(NBPhoneMetaData*)metadata carrierCode:(NSString*)carrierCode
{
    int numberLength = numberStr.length;
    NSString *possibleNationalPrefix = metadata.nationalPrefixForParsing;
    
    if (numberLength == 0 || possibleNationalPrefix == nil || possibleNationalPrefix.length == 0)
    {
        // Early return for numbers of zero length.
        return carrierCode;
    }
    
    // Attempt to parse the first digits as a national prefix.
    NSError *error = nil;
    NSString *prefixPattern = [NSString stringWithFormat:@"^(?:%@)", possibleNationalPrefix];
    NSRegularExpression *currentPattern = [NSRegularExpression regularExpressionWithPattern:prefixPattern options:0 error:&error];
    NSArray *prefixMatcher = [currentPattern matchesInString:numberStr options:0 range:NSMakeRange(0, numberStr.length)];
    
    if (prefixMatcher && prefixMatcher.count > 0)
    {
        NSString *nationalNumberRule = metadata.generalDesc.nationalNumberPattern;
        // prefixMatcher[numOfGroups] == nil implies nothing was captured by the
        // capturing groups in possibleNationalPrefix; therefore, no transformation
        // is necessary, and we just remove the national prefix.
        int numOfGroups = prefixMatcher.count - 1;
        NSString *transformRule = metadata.nationalPrefixTransformRule;
        NSString *transformedNumber = nil;
        BOOL noTransform = [self hasValue:transformRule] || [self hasValue:prefixMatcher[numOfGroups]];
        
        if (noTransform)
        {
            NSString *prefixString = [prefixMatcher objectAtIndex:0];
            transformedNumber = [numberStr substringToIndex:prefixString.length];
        }
        else
        {
            transformedNumber = [numberStr stringByReplacingOccurrencesOfString:prefixPattern withString:transformRule];
        }
        // If the original number was viable, and the resultant number is not,
        // we return.
        if ([self matchesEntirely:nationalNumberRule string:numberStr] &&
            [self matchesEntirely:nationalNumberRule string:transformedNumber] == NO)
        {
            return carrierCode;
        }
        if ((noTransform && numOfGroups > 0 && prefixMatcher[1] != nil) || (!noTransform && numOfGroups > 1))
        {
            if (carrierCode != nil)
            {
                [carrierCode stringByAppendingString:prefixMatcher[1]];
            }
        }
        
        numberStr = [transformedNumber copy];
        return carrierCode;
    }
    return carrierCode;
}


/**
 * Strips any extension (as in, the part of the number dialled after the call is
 * connected, usually indicated with extn, ext, x or similar) from the end of
 * the number, and returns it.
 *
 * @param {!goog.string.StringBuffer} number the non-normalized telephone number
 *     that we wish to strip the extension from.
 * @return {string} the phone extension.
 */
- (NSString*)maybeStripExtension:(NSString*)number
{
    NSString *numberStr = [number copy];
    int mStart = [self stringPositionByRegex:numberStr regex:self.EXTN_PATTERN_];
    
    // If we find a potential extension, and the number preceding this is a viable
    // number, we assume it is an extension.
    if (mStart >= 0 && [self isViablePhoneNumber:[numberStr substringToIndex:mStart]])
    {
        // The numbers are captured into groups in the regular expression.
        NSArray *matchedGroups = [self matchesByRegex:numberStr regex:self.EXTN_PATTERN_];
        int matchedGroupsLength = [matchedGroups count];
        for (int i=1; i<matchedGroupsLength; ++i)
        {
            NSTextCheckingResult *match = [matchedGroups objectAtIndex:i];
            if (match != nil && match.range.length > 0)
            {
                NSString *matchString = [number substringWithRange:match.range];
                // We go through the capturing groups until we find one that captured
                // some digits. If none did, then we will return the empty string.
                NSString *tokenedString = [numberStr substringWithRange:NSMakeRange(0, mStart)];
                number = @"";
                [number stringByAppendingString:tokenedString];

                return matchString;
            }
        }
    }

    return @"";
}


/**
 * Checks to see that the region code used is valid, or if it is not valid, that
 * the number to parse starts with a + symbol so that we can attempt to infer
 * the region from the number.
 * @param {string} numberToParse number that we are attempting to parse.
 * @param {?string} defaultRegion region that we are expecting the number to be
 *     from.
 * @return {boolean} NO if it cannot use the region provided and the region
 *     cannot be inferred.
 * @private
 */
- (BOOL)checkRegionForParsing:(NSString*)numberToParse defaultRegion:(NSString*)defaultRegion
{
    // If the number is nil or empty, we can't infer the region.
    return [self isValidRegionCode:defaultRegion] ||
        (numberToParse != nil && numberToParse.length > 0 && [self isStartingStringByRegex:numberToParse regex:self.LEADING_PLUS_CHARS_PATTERN_]);
}


/**
 * Parses a string and returns it in proto buffer format. This method will throw
 * a {@link i18n.phonenumbers.Error} if the number is not considered to be a
 * possible number. Note that validation of whether the number is actually a
 * valid number for a particular region is not performed. This can be done
 * separately with {@link #isValidNumber}.
 *
 * @param {?string} numberToParse number that we are attempting to parse. This
 *     can contain formatting such as +, ( and -, as well as a phone number
 *     extension. It can also be provided in RFC3966 format.
 * @param {?string} defaultRegion region that we are expecting the number to be
 *     from. This is only used if the number being parsed is not written in
 *     international format. The country_code for the number in this case would
 *     be stored as that of the default region supplied. If the number is
 *     guaranteed to start with a '+' followed by the country calling code, then
 *     'ZZ' or nil can be supplied.
 * @return {i18n.phonenumbers.PhoneNumber} a phone number proto buffer filled
 *     with the parsed number.
 * @throws {i18n.phonenumbers.Error} if the string is not considered to be a
 *     viable phone number or if no default region was supplied and the number
 *     is not in international format (does not start with +).
 */
- (NBPhoneNumber*)parse:(NSString*)numberToParse defaultRegion:(NSString*)defaultRegion
{
    return [self parseHelper:numberToParse defaultRegion:defaultRegion keepRawInput:NO checkRegion:YES];
}


/**
 * Parses a string and returns it in proto buffer format. This method differs
 * from {@link #parse} in that it always populates the raw_input field of the
 * protocol buffer with numberToParse as well as the country_code_source field.
 *
 * @param {string} numberToParse number that we are attempting to parse. This
 *     can contain formatting such as +, ( and -, as well as a phone number
 *     extension.
 * @param {?string} defaultRegion region that we are expecting the number to be
 *     from. This is only used if the number being parsed is not written in
 *     international format. The country calling code for the number in this
 *     case would be stored as that of the default region supplied.
 * @return {i18n.phonenumbers.PhoneNumber} a phone number proto buffer filled
 *     with the parsed number.
 * @throws {i18n.phonenumbers.Error} if the string is not considered to be a
 *     viable phone number or if no default region was supplied.
 */
- (NBPhoneNumber*)parseAndKeepRawInput:(NSString*)numberToParse defaultRegion:(NSString*)defaultRegion
{
    if ([self isValidRegionCode:defaultRegion] == NO)
    {
        if (numberToParse.length > 0 && [numberToParse hasPrefix:@"+"])
        {
            NSException* metaException = [NSException exceptionWithName:@"INVALID_COUNTRY_CODE"
                                                                 reason:[NSString stringWithFormat:@"Invalid country code:%@", numberToParse]
                                                               userInfo:nil];
            @throw metaException;
        }
    }
    return [self parseHelper:numberToParse defaultRegion:defaultRegion keepRawInput:YES checkRegion:YES];
}
                 

/**
 * Parses a string and returns it in proto buffer format. This method is the
 * same as the public {@link #parse} method, with the exception that it allows
 * the default region to be nil, for use by {@link #isNumberMatch}.
 *
 * @param {?string} numberToParse number that we are attempting to parse. This
 *     can contain formatting such as +, ( and -, as well as a phone number
 *     extension.
 * @param {?string} defaultRegion region that we are expecting the number to be
 *     from. This is only used if the number being parsed is not written in
 *     international format. The country calling code for the number in this
 *     case would be stored as that of the default region supplied.
 * @param {boolean} keepRawInput whether to populate the raw_input field of the
 *     phoneNumber with numberToParse.
 * @param {boolean} checkRegion should be set to NO if it is permitted for
 *     the default coregion to be nil or unknown ('ZZ').
 * @return {i18n.phonenumbers.PhoneNumber} a phone number proto buffer filled
 *     with the parsed number.
 * @throws {i18n.phonenumbers.Error}
 * @private
 */
- (NBPhoneNumber*)parseHelper:(NSString*)numberToParse defaultRegion:(NSString*)defaultRegion
                 keepRawInput:(BOOL)keepRawInput checkRegion:(BOOL)checkRegion
{    
    if (numberToParse == nil)
    {
        NSException* metaException = [NSException exceptionWithName:@"NOT_A_NUMBER"
                                                             reason:[NSString stringWithFormat:@"NOT_A_NUMBER:%@", numberToParse]
                                                           userInfo:nil];
        @throw metaException;
    }
    else if (numberToParse.length > MAX_INPUT_STRING_LENGTH_)
    {
        NSException* metaException = [NSException exceptionWithName:@"TOO_LONG"
                                                             reason:[NSString stringWithFormat:@"TOO_LONG:%@", numberToParse]
                                                           userInfo:nil];
        @throw metaException;
    }
    
    NSMutableString *nationalNumber = [[NSMutableString alloc] init];
    [self buildNationalNumberForParsing:numberToParse nationalNumber:nationalNumber];
    
    if ([self isViablePhoneNumber:nationalNumber] == NO)
    {
        NSException* metaException = [NSException exceptionWithName:@"NOT_A_NUMBER"
                                                             reason:[NSString stringWithFormat:@"NOT_A_NUMBER:%@", nationalNumber]
                                                           userInfo:nil];
        @throw metaException;
    }
    
    // Check the region supplied is valid, or that the extracted number starts
    // with some sort of + sign so the number's region can be determined.
    if (checkRegion && [self checkRegionForParsing:nationalNumber defaultRegion:defaultRegion] == NO)
    {
        NSException* metaException = [NSException exceptionWithName:@"INVALID_COUNTRY_CODE"
                                                             reason:[NSString stringWithFormat:@"INVALID_COUNTRY_CODE:%@", defaultRegion]
                                                           userInfo:nil];
        @throw metaException;
    }
    
    NBPhoneNumber *phoneNumber = [[NBPhoneNumber alloc] init];
    if (keepRawInput)
    {
        phoneNumber.rawInput = [numberToParse copy];
    }
    // Attempt to parse extension first, since it doesn't require region-specific
    // data and we want to have the non-normalised number here.
    NSString *extension = [self maybeStripExtension:nationalNumber];
    if (extension.length > 0)
    {
        phoneNumber.extension = [extension copy];
    }
    
    NBPhoneMetaData *regionMetadata = [self getMetadataForRegion:defaultRegion];
    // Check to see if the number is given in international format so we know
    // whether this number is from the default region or not.
    NSMutableString *normalizedNationalNumber = [[NSMutableString alloc] init];
    NSString *countryCode = @"";
    NSString *nationalNumberStr = [nationalNumber copy];
    @try {
        countryCode = [self maybeExtractCountryCode:nationalNumberStr
                                           metadata:regionMetadata
                                     nationalNumber:normalizedNationalNumber
                                       keepRawInput:keepRawInput
                                        phoneNumber:phoneNumber];
    }
    @catch (NSException *e) {
        if ([e.name isEqualToString:@"INVALID_COUNTRY_CODE"] && [self stringPositionByRegex:nationalNumberStr
                                                                                      regex:self.LEADING_PLUS_CHARS_PATTERN_] >= 0)
        {
            // Strip the plus-char, and try again.
            nationalNumberStr = [self replaceStringByRegex:nationalNumberStr regex:self.LEADING_PLUS_CHARS_PATTERN_ withTemplate:@""];
            countryCode = [self maybeExtractCountryCode:nationalNumberStr
                                               metadata:regionMetadata
                                         nationalNumber:normalizedNationalNumber
                                           keepRawInput:keepRawInput
                                            phoneNumber:phoneNumber];
            if ([countryCode isEqualToString:@"0"])
            {
                @throw e;
            }
        }
        else
        {
            @throw e;
        }
    }
    
    if ([countryCode isEqualToString:@"0"] == NO)
    {
        NSString *phoneNumberRegion = [self getRegionCodeForCountryCode:countryCode];
        if (phoneNumberRegion != defaultRegion)
        {
            // Metadata cannot be nil because the country calling code is valid.
            regionMetadata = [self getMetadataForRegionOrCallingCode:countryCode regionCode:phoneNumberRegion];
        }
    }
    else
    {
        // If no extracted country calling code, use the region supplied instead.
        // The national number is just the normalized version of the number we were
        // given to parse.
        [self normalizeSB:nationalNumber];
        normalizedNationalNumber = [NSString stringWithFormat:@"%@%@", normalizedNationalNumber, nationalNumber];
        
        if (defaultRegion != nil)
        {
            countryCode = regionMetadata.countryCode;
            phoneNumber.countryCode = countryCode;
        }
        else if (keepRawInput)
        {
            phoneNumber.countryCode = @"";
        }
    }
    
    if (normalizedNationalNumber.length < MIN_LENGTH_FOR_NSN_)
    {
        NSException* metaException = [NSException exceptionWithName:@"TOO_SHORT_NSN"
                                                             reason:[NSString stringWithFormat:@"TOO_SHORT_NSN:%@", normalizedNationalNumber]
                                                           userInfo:nil];
        @throw metaException;
    }
    
    if (regionMetadata != nil)
    {
        NSString *carrierCode = @"";
        carrierCode = [self maybeStripNationalPrefixAndCarrierCode:normalizedNationalNumber metadata:regionMetadata carrierCode:carrierCode];
        
        if (keepRawInput)
        {
            phoneNumber.PreferredDomesticCarrierCode = [carrierCode copy];
        }
    }
    
    NSString *normalizedNationalNumberStr = normalizedNationalNumber;
    int lengthOfNationalNumber = normalizedNationalNumberStr.length;
    if (lengthOfNationalNumber < MIN_LENGTH_FOR_NSN_)
    {
        NSException* metaException = [NSException exceptionWithName:@"TOO_SHORT_NSN"
                                                             reason:[NSString stringWithFormat:@"TOO_SHORT_NSN:%@", normalizedNationalNumberStr]
                                                           userInfo:nil];
        @throw metaException;
    }
    
    if (lengthOfNationalNumber > MAX_LENGTH_FOR_NSN_)
    {
        NSException* metaException = [NSException exceptionWithName:@"TOO_LONG"
                                                             reason:[NSString stringWithFormat:@"TOO_LONG:%@", normalizedNationalNumberStr]
                                                           userInfo:nil];
        @throw metaException;
    }
    
    if ([normalizedNationalNumberStr hasPrefix:@"0"])
    {
        phoneNumber.italianLeadingZero = YES;
    }
    
    phoneNumber.nationalNumber = normalizedNationalNumberStr;
    return phoneNumber;
}


/**
 * Converts numberToParse to a form that we can parse and write it to
 * nationalNumber if it is written in RFC3966; otherwise extract a possible
 * number out of it and write to nationalNumber.
 *
 * @param {?string} numberToParse number that we are attempting to parse. This
 *     can contain formatting such as +, ( and -, as well as a phone number
 *     extension.
 * @param {!goog.string.StringBuffer} nationalNumber a string buffer for storing
 *     the national significant number.
 * @private
 */
- (NSString *)buildNationalNumberForParsing:(NSString*)numberToParse nationalNumber:(NSString*)nationalNumber
{
    NSMutableString *resNationalNumber = [[NSMutableString alloc] initWithString:nationalNumber];
    int indexOfPhoneContext = [self indexOfStringByString:numberToParse target:RFC3966_PHONE_CONTEXT_];
    if (indexOfPhoneContext >= 0)
    {
        int phoneContextStart = indexOfPhoneContext + RFC3966_PHONE_CONTEXT_.length;
        // If the phone context contains a phone number prefix, we need to capture
        // it, whereas domains will be ignored.
        if ([numberToParse characterAtIndex:phoneContextStart] == '+')
        {
            // Additional parameters might follow the phone context. If so, we will
            // remove them here because the parameters after phone context are not
            // important for parsing the phone number.
            int phoneContextEnd = [self indexOfStringByString:numberToParse target:@";"];
            if (phoneContextEnd > 0)
            {
                [resNationalNumber appendString:[numberToParse substringWithRange:NSMakeRange(phoneContextStart, phoneContextEnd)]];
            }
            else
            {
                [resNationalNumber appendString:[numberToParse substringFromIndex:phoneContextStart]];
            }
        }
        
        // Now append everything between the "tel:" prefix and the phone-context.
        // This should include the national number, an optional extension or
        // isdn-subaddress component.
        int rfc3966Start = [self indexOfStringByString:numberToParse target:RFC3966_PREFIX_] + RFC3966_PREFIX_.length;
        NSString *subString = [numberToParse substringWithRange:NSMakeRange(rfc3966Start, indexOfPhoneContext)];
        [resNationalNumber stringByAppendingString:subString];
    }
    else
    {
        // Extract a possible number from the string passed in (this strips leading
        // characters that could not be the start of a phone number.)
        [resNationalNumber stringByAppendingString:[self extractPossibleNumber:numberToParse]];
    }
    
    // Delete the isdn-subaddress and everything after it if it is present.
    // Note extension won't appear at the same time with isdn-subaddress
    // according to paragraph 5.3 of the RFC3966 spec,
    NSString *nationalNumberStr = [nationalNumber copy];
    int indexOfIsdn = [self indexOfStringByString:nationalNumberStr target:RFC3966_ISDN_SUBADDRESS_];
    if (indexOfIsdn > 0)
    {
        nationalNumber = @"";
        [nationalNumber stringByAppendingString:[nationalNumberStr substringWithRange:NSMakeRange(0, indexOfIsdn)]];
    }
    // If both phone context and isdn-subaddress are absent but other
    // parameters are present, the parameters are left in nationalNumber. This
    // is because we are concerned about deleting content from a potential
    // number string when there is no strong evidence that the number is
    // actually written in RFC3966.
    
    return resNationalNumber;
}


/**
 * Takes two phone numbers and compares them for equality.
 *
 * <p>Returns EXACT_MATCH if the country_code, NSN, presence of a leading zero
 * for Italian numbers and any extension present are the same. Returns NSN_MATCH
 * if either or both has no region specified, and the NSNs and extensions are
 * the same. Returns SHORT_NSN_MATCH if either or both has no region specified,
 * or the region specified is the same, and one NSN could be a shorter version
 * of the other number. This includes the case where one has an extension
 * specified, and the other does not. Returns NO_MATCH otherwise. For example,
 * the numbers +1 345 657 1234 and 657 1234 are a SHORT_NSN_MATCH. The numbers
 * +1 345 657 1234 and 345 657 are a NO_MATCH.
 *
 * @param {i18n.phonenumbers.PhoneNumber|string} firstNumberIn first number to
 *     compare. If it is a string it can contain formatting, and can have
 *     country calling code specified with + at the start.
 * @param {i18n.phonenumbers.PhoneNumber|string} secondNumberIn second number to
 *     compare. If it is a string it can contain formatting, and can have
 *     country calling code specified with + at the start.
 * @return {MatchType} NOT_A_NUMBER, NO_MATCH,
 *     SHORT_NSN_MATCH, NSN_MATCH or EXACT_MATCH depending on the level of
 *     equality of the two numbers, described in the method definition.
 */
- (NBEMatchType)isNumberMatch:(id)firstNumberIn second:(id)secondNumberIn
{
    
    // If the input arguements are strings parse them to a proto buffer format.
    // Else make copies of the phone numbers so that the numbers passed in are not
    // edited.
    /** @type {i18n.phonenumbers.PhoneNumber} */
    NBPhoneNumber *firstNumber = nil, *secondNumber = nil;
    if ([firstNumberIn isKindOfClass:[NSString class]])
    {
        // First see if the first number has an implicit country calling code, by
        // attempting to parse it.
        @try {
            firstNumber = [self parse:(NSString*)firstNumberIn defaultRegion:UNKNOWN_REGION_];
        }
        @catch (NSException *e) {
            if ([e.name isEqualToString:@"INVALID_COUNTRY_CODE"] == NO)
            {
                return NOT_A_NUMBER;
            }
            // The first number has no country calling code. EXACT_MATCH is no longer
            // possible. We parse it as if the region was the same as that for the
            // second number, and if EXACT_MATCH is returned, we replace this with
            // NSN_MATCH.
            if ([secondNumberIn isKindOfClass:[NBPhoneNumber class]])
            {
                NSString *secondNumberRegion = [self getRegionCodeForCountryCode:((NBPhoneNumber*)secondNumberIn).countryCode];
                if (secondNumberRegion != UNKNOWN_REGION_)
                {
                    @try {
                        firstNumber = [self parse:(NSString*)firstNumberIn defaultRegion:secondNumberRegion];
                    }
                    @catch (NSException *e2) {
                        return NOT_A_NUMBER;
                    }
                    
                    NBEMatchType match = [self isNumberMatch:firstNumber second:secondNumberIn];
                    if (match == EXACT_MATCH)
                    {
                        return NSN_MATCH;
                    }
                    return match;
                }
            }
            // If the second number is a string or doesn't have a valid country
            // calling code, we parse the first number without country calling code.
            @try {
                firstNumber = [self parseHelper:firstNumberIn defaultRegion:nil keepRawInput:NO checkRegion:NO];
            }
            @catch (NSException *e2)  {
                return NOT_A_NUMBER;
            }
        }
    }
    else
    {
        firstNumber = [firstNumberIn copy];
    }
    
    if ([secondNumberIn isKindOfClass:[NSString class]])
    {
        @try {
            secondNumber = [self parse:secondNumberIn defaultRegion:UNKNOWN_REGION_];
            return [self isNumberMatch:firstNumberIn second:(NSString*)secondNumber];
        }
        @catch (NSException *e2) {
            if ([e2.name isEqualToString:@"INVALID_COUNTRY_CODE"] == NO)
            {
                return NOT_A_NUMBER;
            }
            return [self isNumberMatch:secondNumberIn second:firstNumber];
        }
    }
    else
    {
        secondNumber = [secondNumberIn copy];
    }
    
    // First clear raw_input, country_code_source and
    // preferred_domestic_carrier_code fields and any empty-string extensions so
    // that we can use the proto-buffer equality method.
    firstNumber.rawInput = @"";
    [firstNumber clearCountryCodeSource];
    firstNumber.PreferredDomesticCarrierCode = @"";
    
    secondNumber.rawInput = @"";
    [secondNumber clearCountryCodeSource];
    secondNumber.PreferredDomesticCarrierCode = @"";
    
    if (firstNumber.extension != nil && firstNumber.extension.length == 0)
    {
        firstNumber.extension = nil;
    }
    
    if (secondNumber.extension != nil && secondNumber.extension.length == 0)
    {
        secondNumber.extension = nil;
    }
    
    // Early exit if both had extensions and these are different.
    if ([self hasValue:firstNumber.extension] && [self hasValue:secondNumber.extension] &&
        [firstNumber.extension isEqualToString:secondNumber.extension] == NO)
    {
        return NO_MATCH;
    }

    NSString *firstNumberCountryCode = firstNumber.countryCode;
    NSString *secondNumberCountryCode = secondNumber.countryCode;
    
    // Both had country_code specified.
    if ([firstNumberCountryCode isEqualToString:@"0"] == NO && [secondNumberCountryCode isEqualToString:@"0"] == NO)
    {
        if ([firstNumber isEqual:secondNumber])
        {
            return EXACT_MATCH;
        }
        else if ([firstNumberCountryCode isEqualToString:secondNumberCountryCode] && [self isNationalNumberSuffixOfTheOther:firstNumber second:secondNumber])
        {
            // A SHORT_NSN_MATCH occurs if there is a difference because of the
            // presence or absence of an 'Italian leading zero', the presence or
            // absence of an extension, or one NSN being a shorter variant of the
            // other.
            return SHORT_NSN_MATCH;
        }
        // This is not a match.
        return NO_MATCH;
    }
    // Checks cases where one or both country_code fields were not specified. To
    // make equality checks easier, we first set the country_code fields to be
    // equal.
    firstNumber.countryCode = @"0";
    secondNumber.countryCode = @"0";
    // If all else was the same, then this is an NSN_MATCH.
    if ([firstNumber isEqual:secondNumber])
    {
        return NSN_MATCH;
    }
    
    if ([self isNationalNumberSuffixOfTheOther:firstNumber second:secondNumber])
    {
        return SHORT_NSN_MATCH;
    }
    return NO_MATCH;
}


/**
 * Returns NO when one national number is the suffix of the other or both are
 * the same.
 *
 * @param {i18n.phonenumbers.PhoneNumber} firstNumber the first PhoneNumber
 *     object.
 * @param {i18n.phonenumbers.PhoneNumber} secondNumber the second PhoneNumber
 *     object.
 * @return {boolean} NO if one PhoneNumber is the suffix of the other one.
 * @private
 */
- (BOOL)isNationalNumberSuffixOfTheOther:(NBPhoneNumber*)firstNumber second:(NBPhoneNumber*)secondNumber
{
    NSString *firstNumberNationalNumber = firstNumber.nationalNumber;
    NSString *secondNumberNationalNumber = secondNumber.nationalNumber;
    // Note that endsWith returns NO if the numbers are equal.
    return [firstNumberNationalNumber hasSuffix:secondNumberNationalNumber] ||
        [secondNumberNationalNumber hasSuffix:firstNumberNationalNumber];
}


/**
 * Returns NO if the number can be dialled from outside the region, or
 * unknown. If the number can only be dialled from within the region, returns
 * NO. Does not check the number is a valid number.
 * TODO: Make this method public when we have enough metadata to make it
 * worthwhile. Currently visible for testing purposes only.
 *
 * @param {i18n.phonenumbers.PhoneNumber} number the phone-number for which we
 *     want to know whether it is diallable from outside the region.
 * @return {boolean} NO if the number can only be dialled from within the
 *     country.
 */
- (BOOL)canBeInternationallyDialled:(NBPhoneNumber*)number
{
    NBPhoneMetaData *metadata = [self getMetadataForRegion:[self getRegionCodeForNumber:number]];
    if (metadata == nil)
    {
        // Note numbers belonging to non-geographical entities (e.g. +800 numbers)
        // are always internationally diallable, and will be caught here.
        return NO;
    }
    NSString *nationalSignificantNumber = [self getNationalSignificantNumber:number];
    return [self isNumberMatchingDesc:nationalSignificantNumber numberDesc:metadata.noInternationalDialling] == NO;
}


/**
 * Check whether the entire input sequence can be matched against the regular
 * expression.
 *
 * @param {!RegExp|string} regex the regular expression to match against.
 * @param {string} str the string to test.
 * @return {boolean} NO if str can be matched entirely against regex.
 * @private
 */
- (BOOL)matchesEntirely:(NSString*)regex string:(NSString*)str
{
    NSError *error = nil;
    NSRegularExpression *currentPattern = [NSRegularExpression regularExpressionWithPattern:regex options:0 error:&error];
    NSArray *matches = [currentPattern matchesInString:str options:0 range:NSMakeRange(0, str.length)];
    
    if (matches && [matches count] > 0)
    {
        NSTextCheckingResult *currentMatch = [matches objectAtIndex:0];
        NSString *founds = [str substringWithRange:currentMatch.range];
        if ([founds isEqualToString:str])
        {
            return YES;
        }
    }
    return NO;
}


@end