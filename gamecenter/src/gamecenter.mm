/*******************************************************************************
 * Licensed to the Apache Software Foundation (ASF) under one
 * or more contributor license agreements.  See the NOTICE file
 * distributed with this work for additional information
 * regarding copyright ownership.  The ASF licenses this file
 * to you under the Apache License, Version 2.0 (the
 * "License"); you may not use this file except in compliance
 * with the License.  You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing,
 * software distributed under the License is distributed on an
 * "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 * KIND, either express or implied.  See the License for the
 * specific language governing permissions and limitations
 * under the License.
 *******************************************************************************/

#include <dmsdk/sdk.h>
#include <vector>
#include <map>
#include <string>

#include "gamecenter_private.h"
#include <Foundation/Foundation.h>
#include <GameKit/GameKit.h>

#if defined(DM_PLATFORM_IOS)
#include <UIKit/UIKit.h>
#endif

using namespace std;

#if defined(DM_PLATFORM_IOS) || defined(DM_PLATFORM_OSX)
NSString *const PresentAuthenticationViewController = @"present_authentication_view_controller";

@protocol GameCenterManagerDelegate <GKGameCenterControllerDelegate>
@end

#if defined(DM_PLATFORM_IOS)
@interface GameKitManager : UIViewController <GameCenterManagerDelegate>
{
@private UIViewController *m_authenticationViewController;
#else
@interface GameKitManager : NSViewController <GameCenterManagerDelegate>
{
@private NSViewController *m_authenticationViewController;
#endif

@private id<GameCenterManagerDelegate, NSObject> m_delegate;
}
+ (instancetype)sharedGameKitManager;
@end


@implementation GameKitManager

+ (instancetype)sharedGameKitManager
{
    static GameKitManager *sharedGameKitManager;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedGameKitManager = [[GameKitManager alloc] init];
    });
    return sharedGameKitManager;
}

- (id)init
{
    self = [super init];
    if (self) {
    	m_delegate = self;
    }
    return self;
}

- (void)authenticateLocalPlayer:(CallbackFn) fn withCallbackInfo:(CallbackInfo*) cbk
{
    NSLog (@"Authenticating local user...");
    @try {
    GKLocalPlayer *localPlayer = [GKLocalPlayer localPlayer];

#if defined(DM_PLATFORM_IOS)
    localPlayer.authenticateHandler  =
    ^(UIViewController *viewController, NSError *error) {
#else
    localPlayer.authenticateHandler  =
    ^(NSViewController *viewController, NSError *error) {
#endif

            if(viewController != nil) {
                NSLog (@"Game Center: User was not logged in. Show Login Screen.");
                [self setAuthenticationViewController:viewController];
            } else if([GKLocalPlayer localPlayer].isAuthenticated) {
                NSLog (@"Game Center: You are logged in to game center.");
                NSString *playerID=localPlayer.playerID;
                NSString *alias=localPlayer.alias;
                cbk->m_playerID=[playerID UTF8String];
                cbk->m_alias=[alias UTF8String];
                fn(cbk);
            } else if (error != nil) {
                NSLog (@"Game Center: Error occurred authenticating-");
				NSLog (@"  %@", [error localizedDescription]);
                cbk->m_Error = new GKError([error code], [[error localizedDescription] UTF8String]);
            } else {
            	cbk->m_Error = new GKError(GKErrorUnknown, "Unknown");
            	fn(cbk);
            }
        };
    }
    @catch (NSException *exception){
        NSLog(@"authenticateLocalPlayer Caught an exception");
    }
    @finally{
        NSLog(@"authenticateLocalPlayer Cleaning up");
    }
}

#if defined(DM_PLATFORM_IOS)
- (void)setAuthenticationViewController:(UIViewController *)authenticationViewController
#else
- (void)setAuthenticationViewController:(NSViewController *)authenticationViewController
#endif
	{
    @try {
        m_authenticationViewController = authenticationViewController;
        [[NSNotificationCenter defaultCenter]
        postNotificationName:PresentAuthenticationViewController
        object:self];
    }
    @catch (NSException *exception){
        NSLog(@"setAuthenticationViewController Caught an exception");
    }
}


- (bool) isGameCenterAvailable {

    bool status=false;
    NSLog(@"is available?");
    @try {
        // check for presence of GKLocalPlayer API
        //Class gcClass = NSClassFromString(@"GKLocalPlayer");
        //if (gcClass){ status=true;}
        status=true; //for debug reasone. Not sure why, but NSClassFromString getting hard-crash.
    }
    @catch (NSException *exception){
        NSLog(@"isGameCenterAvailable Caught an exception");
    }
        // check if the device is running iOS 4.1 or later
        //NSString* reqSysVer = @"4.1";
        //NSString* currSysVer = [[UIDevice currentDevice] systemVersion];
        //BOOL osVersionSupported = ([currSysVer compare:reqSysVer options:NSNumericSearch] != NSOrderedAscending);
        //return (gcClass && osVersionSupported);
    return status;

}

- (void) login:(CallbackFn) fn withCallbackInfo:(CallbackInfo*) cbk
{
    @try {

        if (isGameCenterAvailable()==true) {
             NSLog(@"login in GameCenter is available");
            [[NSNotificationCenter defaultCenter]
             addObserver:self
             selector:@selector(showAuthenticationViewController)
             name:PresentAuthenticationViewController
             object:nil];

            [self authenticateLocalPlayer:fn withCallbackInfo:cbk];
        } else {
            NSLog(@"GameCenter is not available");
            cbk->m_Error = new GKError(GKErrorUnknown, "GameCenter is not available");
            fn(cbk);
        }
    }
    @catch (NSException *exception){
        NSLog(@"login Caught an exception");
        cbk->m_Error = new GKError(GKErrorUnknown, "Exception");
        fn(cbk);
    }
}

- (void) reportScore:(NSString*)leaderboardId score:(int)score withCallback:(CallbackFn) fn withCallbackInfo:(CallbackInfo*) cbk
{
    GKScore* scoreReporter = [[GKScore alloc] initWithLeaderboardIdentifier:leaderboardId];
    scoreReporter.value = (int64_t)score;
    [GKScore reportScores:@[scoreReporter] withCompletionHandler:^(NSError *error) {
        if (error)
        {
            cbk->m_Error = new GKError([error code], [[error localizedDescription] UTF8String]);
        }
        fn(cbk);
    }];
}

- (void)submitAchievement:(NSString*)identifier withPercentComplete:(double)percentComplete withCallback:(CallbackFn)fn withCallbackInfo:(CallbackInfo*) cbk
{
    GKAchievement *achievement = [[[GKAchievement alloc] initWithIdentifier:identifier]  autorelease];
    [achievement setPercentComplete:percentComplete];
    achievement.showsCompletionBanner = YES;
    [achievement reportAchievementWithCompletionHandler:^(NSError  *error) {
        if (error)
        {
            cbk->m_Error = new GKError([error code], [[error localizedDescription] UTF8String]);
        }
        fn(cbk);
    }];
}

- (void)loadAchievements:(CallbackFn)fn withCallbackInfo:(CallbackInfo*) cbk {
        [GKAchievement loadAchievementsWithCompletionHandler:^(NSArray *achievements, NSError *error) {
            if (error == NULL)
            {
                if(achievements != NULL && achievements.count > 0) {
                	cbk->m_achievements.OffsetCapacity(achievements.count);
	                for (GKAchievement *achievement in achievements)
	                {
	                   cbk->m_achievements.Push(SAchievement([achievement.identifier UTF8String], achievement.percentComplete));
	                }
                }
            } else {
                cbk->m_Error = new GKError([error code], [[error localizedDescription] UTF8String]);
            }
            fn(cbk);
        }];
}

- (void)resetAchievements:(CallbackFn)fn withCallbackInfo:(CallbackInfo*) cbk {
    [GKAchievement resetAchievementsWithCompletionHandler:^(NSError *error) {
        if (error)
        {
            cbk->m_Error = new GKError([error code], [[error localizedDescription] UTF8String]);
        }
        fn(cbk);
    }];
}

//- (void) saveGame:(NSData*)data withName:(NSString*)name withCallback:(CallbackFn)fn withCallbackInfo:(CallbackInfo*) cbk
- (void) saveGameString:(NSString*)str withName:(NSString*)name withCallback:(CallbackFn)fn withCallbackInfo:(CallbackInfo*) cbk
{
//- (void)saveGameData:(NSData *)data withName:(NSString *)name completionHandler:(void (^)(GKSavedGame *savedGame, NSError *error))handler;
// NSData *data = [NSData data];
//NSString *string = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];

//NSString *str = @"helowrld";
// This converts the string to an NSData object
  NSLog(@"GameCenter.saveGameString %@",str);
  NSData *data = [str dataUsingEncoding:NSUTF8StringEncoding];
  //GKSavedGame *savedGame=[[GKSavedGame alloc]]
  GKLocalPlayer *localPlayer = [GKLocalPlayer localPlayer];
  NSLog(@"Player=%@ , data=%@, name=%@", localPlayer, data, name);

  [localPlayer saveGameData:data withName:name completionHandler:^(GKSavedGame *savedGame, NSError *error) {
    if (savedGame != nil) { NSLog(@"Player data saved to GameCenter"); }else{ NSLog(@"Player=%@ data NOT saved to GameCenter, error=%@", localPlayer, error.description);}
        if (error)
        {
            cbk->m_Error = new GKError([error code], [[error localizedDescription] UTF8String]);
        }
        fn(cbk);
  }];

}

//- (void)fetchSavedGamesWithCompletionHandler:(void (^)(NSArray<GKSavedGame *> *savedGames, NSError *error))handler;
//- (void)loadDataWithCompletionHandler:(void (^)(NSData *data, NSError *error))handler;


// BEGIN SHOW THE STANDARD USER INTERFACE
- (void)showAuthenticationViewController
{
#if defined(DM_PLATFORM_IOS)
    [[UIApplication sharedApplication].keyWindow.rootViewController presentViewController:
     m_authenticationViewController
                                                                                 animated:YES
                                                                               completion:nil];
#else
    [self presentViewControllerAsModalWindow:m_authenticationViewController];
#endif
}

- (void)showLeaderboards:(NSString*)leaderboardId withTimeScope:(int)timeScope {
    [self showLeaderboard:leaderboardId withTimeScope:timeScope];
}

- (void)showLeaderboards:(int)timeScope {
    [self showLeaderboard:nil withTimeScope:timeScope];
}

- (void)showLeaderboard:(NSString*)leaderboardId withTimeScope:(int)timeScope {
    GKGameCenterViewController* gameCenterController = [[GKGameCenterViewController alloc] init];
    gameCenterController.viewState = GKGameCenterViewControllerStateLeaderboards;
    gameCenterController.leaderboardTimeScope = (GKLeaderboardTimeScope)timeScope;
    if(leaderboardId != nil) {
        gameCenterController.leaderboardIdentifier = leaderboardId;
    }
    gameCenterController.gameCenterDelegate = self;

#if defined(DM_PLATFORM_IOS)
    [[UIApplication sharedApplication].keyWindow.rootViewController presentViewController:
     gameCenterController animated:YES completion:nil];
#else
    [self presentViewControllerAsModalWindow:gameCenterController];
#endif
}

- (void)showAchievements {
    GKGameCenterViewController* gameCenterController = [[GKGameCenterViewController alloc] init];
    gameCenterController.viewState = GKGameCenterViewControllerStateAchievements;
    gameCenterController.gameCenterDelegate = self;

#if defined(DM_PLATFORM_IOS)
    [[UIApplication sharedApplication].keyWindow.rootViewController presentViewController:
     gameCenterController animated:YES completion:nil];
#else
    [self presentViewControllerAsModalWindow:gameCenterController];
#endif
}
// END SHOW THE STANDARD USER INTERFACE


// BEGIN DELEGATE
- (void)gameCenterViewControllerDidFinish:(GKGameCenterViewController*) gameCenterViewController {
#if defined(DM_PLATFORM_IOS)
    [[UIApplication sharedApplication].keyWindow.rootViewController dismissViewControllerAnimated:true completion:nil];
#else
    [self dismissViewController:gameCenterViewController];
#endif
}

//END DELEGATE

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end

// BEGIN API

bool isGameCenterAvailable(){
    //[[GameKitManager sharedGameKitManager] isGameCenterAvailable];
    return true;
}

void login(CallbackFn fn , CallbackInfo* cbk) {
    [[GameKitManager sharedGameKitManager] login:fn withCallbackInfo:cbk];
}

void reportScore(const char *leaderboardId, int score, CallbackFn fn , CallbackInfo* cbk) {
    [[GameKitManager sharedGameKitManager] reportScore:@(leaderboardId) score:score withCallback:fn withCallbackInfo:cbk];
}

void showLeaderboards(int timeScope) {
    [[GameKitManager sharedGameKitManager] showLeaderboards:timeScope];
}

void showLeaderboards(const char *leaderboardId, int timeScope) {
    [[GameKitManager sharedGameKitManager] showLeaderboards:@(leaderboardId) withTimeScope:timeScope];
}

void showAchievements() {
    [[GameKitManager sharedGameKitManager] showAchievements];
}

void submitAchievement(const char *identifier, double percentComplete, CallbackFn fn , CallbackInfo* cbk) {
    [[GameKitManager sharedGameKitManager] submitAchievement:@(identifier) withPercentComplete:percentComplete withCallback:fn withCallbackInfo:cbk];
}

void loadAchievements(CallbackFn fn , CallbackInfo* cbk) {
    [[GameKitManager sharedGameKitManager] loadAchievements:fn withCallbackInfo:cbk];
}

void resetAchievements(CallbackFn fn , CallbackInfo* cbk) {
    [[GameKitManager sharedGameKitManager] resetAchievements:fn withCallbackInfo:cbk];
}

void saveGameString(const char*str, const char* name, CallbackFn fn,CallbackInfo* cbk){
  [[GameKitManager sharedGameKitManager] saveGameString:@(str) withName:@(name) withCallback:fn withCallbackInfo:cbk];
}

bool testBool(){
  return true;
}
// END API

#endif // DM_PLATFORM_IOS/DM_PLATFORM_OSX
