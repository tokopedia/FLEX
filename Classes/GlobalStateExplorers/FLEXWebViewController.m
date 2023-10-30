//
//  FLEXWebViewController.m
//  Flipboard
//
//  Created by Ryan Olson on 6/10/14.
//  Copyright (c) 2020 FLEX Team. All rights reserved.
//

#import "FLEXWebViewController.h"
#import "FLEXUtility.h"
#import <WebKit/WebKit.h>

@interface FLEXWebViewController () <WKNavigationDelegate, UISearchBarDelegate>

@property (nonatomic) WKWebView *webView;
@property (nonatomic) NSString *originalText;
@property (nonatomic) UISearchBar *searchBar;
@property (nonatomic) UIBarButtonItem *searchBarButton;
@property (nonatomic) NSString *searchText;
@property (nonatomic) UILabel *searchInfoLabel;

@end

@implementation FLEXWebViewController

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil {
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        WKWebViewConfiguration *configuration = [WKWebViewConfiguration new];

        if (@available(iOS 10.0, *)) {
            configuration.dataDetectorTypes = WKDataDetectorTypeLink;
        }

        self.webView = [[WKWebView alloc] initWithFrame:CGRectZero configuration:configuration];
        self.webView.navigationDelegate = self;
    }
    return self;
}

- (id)initWithText:(NSString *)text {
    self = [self initWithNibName:nil bundle:nil];
    if (self) {
        self.originalText = text;

        NSString *html = @"<head><style>:root{ color-scheme: light dark; }</style>"
            "<meta name='viewport' content='initial-scale=1.0'></head><body><pre>%@</pre></body>";

        // Loading message for when input text takes a long time to escape
        NSString *loadingMessage = [NSString stringWithFormat:html, @"Loading..."];
        [self.webView loadHTMLString:loadingMessage baseURL:nil];

        // Escape HTML on a background thread
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            NSString *escapedText = [FLEXUtility stringByEscapingHTMLEntitiesInString:text];
            NSString *htmlString = [NSString stringWithFormat:html, escapedText];

            // Update webview on the main thread
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.webView loadHTMLString:htmlString baseURL:nil];
            });
        });
    }

    return self;
}

- (id)initWithURL:(NSURL *)url {
    self = [self initWithNibName:nil bundle:nil];
    if (self) {
        NSURLRequest *request = [NSURLRequest requestWithURL:url];
        [self.webView loadRequest:request];
    }

    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    [self.view addSubview:self.webView];
    self.webView.frame = self.view.bounds;
    self.webView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    
    if (self.originalText.length > 0) {
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
            initWithTitle:@"Copy" style:UIBarButtonItemStylePlain target:self action:@selector(copyButtonTapped:)
        ];
    }
    // Create the search bar button and add it to the navigation item
    self.searchBarButton = [[UIBarButtonItem alloc]
                            initWithBarButtonSystemItem:UIBarButtonSystemItemSearch
                            target:self action:@selector(searchButtonTapped:)
    ];
    self.navigationItem.rightBarButtonItems = @[self.searchBarButton, self.navigationItem.rightBarButtonItem];
}

- (void)copyButtonTapped:(id)sender {
    [UIPasteboard.generalPasteboard setString:self.originalText];
}


#pragma mark - WKWebView Delegate

- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction
                                                     decisionHandler:(void (^)(WKNavigationActionPolicy))handler {
    WKNavigationActionPolicy policy = WKNavigationActionPolicyCancel;
    if (navigationAction.navigationType == WKNavigationTypeOther) {
        // Allow the initial load
        policy = WKNavigationActionPolicyAllow;
    } else {
        // For clicked links, push another web view controller onto the navigation stack
        // so that hitting the back button works as expected.
        // Don't allow the current web view to handle the navigation.
        NSURLRequest *request = navigationAction.request;
        FLEXWebViewController *webVC = [[[self class] alloc] initWithURL:request.URL];
        webVC.title = request.URL.absoluteString;
        [self.navigationController pushViewController:webVC animated:YES];
    }

    handler(policy);
}


#pragma mark - Class Helpers

+ (BOOL)supportsPathExtension:(NSString *)extension {
    BOOL supported = NO;
    NSSet<NSString *> *supportedExtensions = [self webViewSupportedPathExtensions];
    if ([supportedExtensions containsObject:extension.lowercaseString]) {
        supported = YES;
    }
    return supported;
}

+ (NSSet<NSString *> *)webViewSupportedPathExtensions {
    static NSSet<NSString *> *pathExtensions = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // Note that this is not exhaustive, but all these extensions should work well in the web view.
        // See https://developer.apple.com/library/archive/documentation/AppleApplications/Reference/SafariWebContent/CreatingContentforSafarioniPhone/CreatingContentforSafarioniPhone.html#//apple_ref/doc/uid/TP40006482-SW7
        pathExtensions = [NSSet<NSString *> setWithArray:@[
            @"jpg", @"jpeg", @"png", @"gif", @"pdf", @"svg", @"tiff", @"3gp", @"3gpp", @"3g2",
            @"3gp2", @"aiff", @"aif", @"aifc", @"cdda", @"amr", @"mp3", @"swa", @"mp4", @"mpeg",
            @"mpg", @"mp3", @"wav", @"bwf", @"m4a", @"m4b", @"m4p", @"mov", @"qt", @"mqv", @"m4v"
        ]];
        
    });

    return pathExtensions;
}

- (void)loadWebViewContent {
    if (self.originalText.length > 0) {
        NSString *html = [NSString stringWithFormat:@"<head><style>:root{ color-scheme: light dark; }</style>"
                          "<meta name='viewport' content='initial-scale=1.0'></head><body><pre>%@</pre></body>", self.originalText];
        [self.webView loadHTMLString:html baseURL:nil];
    }
}

#pragma mark - Search Bar
- (void)searchButtonTapped:(id)sender {
    // Remove the old highlighted results if any
    if (self.searchText.length > 0) {
        self.searchText = nil;
        [self loadWebViewContent]; // Reset the WKWebView content to the original state
    }
    
    // Create and display the search bar
    self.searchBar = [[UISearchBar alloc] init];
    self.searchBar.delegate = self;
    self.searchBar.showsCancelButton = YES;
    self.searchBar.placeholder = @"Search";
    self.searchBar.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.navigationItem.titleView = self.searchBar;
    
    // Create and display the search info label if not added already
    if (![self.searchInfoLabel isDescendantOfView:self.view]) {
        self.searchInfoLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, self.view.bounds.size.height - 44, self.view.bounds.size.width, 44)];
        self.searchInfoLabel.backgroundColor = [UIColor lightGrayColor];
        self.searchInfoLabel.textColor = [UIColor blackColor];
        self.searchInfoLabel.textAlignment = NSTextAlignmentCenter;
        [self.view addSubview:self.searchInfoLabel];
    }
    self.searchInfoLabel.text = @"";
    [self.searchBar becomeFirstResponder];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
    self.searchText = searchBar.text;
    [self resetHighlightedText];
    [self searchAndHighlightText];
}

- (void)searchAndHighlightText {
    if (self.searchText.length > 0) {
        NSString *searchText = self.searchText;
        NSString *javascript = [NSString stringWithFormat:@""
                                "function highlightText(text) {"
                                " var elements = document.querySelectorAll(':not([hidden]) *');"
                                " var count = 0;"
                                " for (var i = 0; i < elements.length; i++) {"
                                "  var innerHTML = elements[i].innerHTML;"
                                "  var searchRegEx = new RegExp(text, 'gi');"
                                "  var matches = innerHTML.match(searchRegEx);"
                                "  if (matches) {"
                                "    innerHTML = innerHTML.replace(searchRegEx, '<span style=\"background-color: yellow;\">' + text + '</span>');"
                                "    count += matches.length;"
                                "  }"
                                "  elements[i].innerHTML = innerHTML;"
                                " }"
                                " return count / 2;" // Divide by 2 to account for two separate search texts
                                "};"
                                "var result = highlightText('%@');"
                                "result;", searchText];
        
        [self.webView evaluateJavaScript:javascript completionHandler:^(id result, NSError *error) {
            if (!error) {
                // Update the search info label with the correct number of results found
                self.searchInfoLabel.text = [NSString stringWithFormat:@"%ld results found", (long)[result integerValue]];
            } else {
                NSLog(@"JavaScript evaluation error: %@", error);
            }
        }];
    }
}

- (void)searchBarCancelButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
    self.searchText = nil;
    self.navigationItem.titleView = nil; // Remove the search bar from the navigation item
    [self.searchInfoLabel removeFromSuperview]; // Remove the search info label
    [self loadWebViewContent]; // Reset the WKWebView content to the original state
}

- (void)resetHighlightedText {
    NSString *javascript = @""
    "function resetHighlight() {"
    "  var elements = document.getElementsByTagName('span');"
    "  for (var i = 0; i < elements.length; i++) {"
    "    if (elements[i].style.backgroundColor === 'yellow') {"
    "      elements[i].style.backgroundColor = 'transparent';"
    "    }"
    "  }"
    "};"
    "resetHighlight();";
    
    [self.webView evaluateJavaScript:javascript completionHandler:^(id result, NSError *error) {
        if (!error) {
            self.searchInfoLabel.text = @"";
        } else {
            NSLog(@"JavaScript evaluation error: %@", error);
        }
    }];
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    self.searchText = searchText;
    if (searchText.length == 0) {
        [self resetHighlightedText];
    }
}

@end
