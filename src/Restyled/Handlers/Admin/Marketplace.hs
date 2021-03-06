{-# LANGUAGE TemplateHaskell #-}

module Restyled.Handlers.Admin.Marketplace
    ( getAdminMarketplaceR
    )
where

import Restyled.Prelude

import Data.List (nub)
import Restyled.Backend.Marketplace (isPrivateRepoPlan)
import Restyled.Foundation
import Restyled.Models
import Restyled.Settings
import Restyled.Yesod

data MarketplacePlanWithAccounts = MarketplacePlanWithAccounts
    { mpwaPlan :: Entity MarketplacePlan
    , mpwaAccounts :: [Entity MarketplaceAccount]
    }

mpwaDescription :: MarketplacePlanWithAccounts -> Text
mpwaDescription = marketplacePlanDescription . entityVal . mpwaPlan

mpwaOwnerNames :: MarketplacePlanWithAccounts -> [OwnerName]
mpwaOwnerNames = map (accountOwner . entityVal) . mpwaAccounts
    where accountOwner = nameToName . marketplaceAccountGithubLogin

getAdminMarketplaceR :: Handler Html
getAdminMarketplaceR = do
    (plans, noPlanRepoOwners) <- runDB $ do
        plans' <- selectList [] [Asc MarketplacePlanGithubId]
        plans <- for plans' $ \plan ->
            MarketplacePlanWithAccounts plan <$> selectList
                [MarketplaceAccountMarketplacePlan ==. entityKey plan]
                [Asc MarketplaceAccountGithubId]

        let planOwners = concatMap mpwaOwnerNames plans
        (plans, ) <$> fetchUniqueRepoOwnersExcept planOwners

    adminLayout $ do
        setTitle "Admin - Marketplace"
        $(widgetFile "admin/marketplace")

fetchUniqueRepoOwnersExcept
    :: MonadIO m => [OwnerName] -> SqlPersistT m [OwnerName]
fetchUniqueRepoOwnersExcept exceptOwners = do
    owners <- repoOwner . entityVal <$$> selectList
        [RepoOwner /<-. exceptOwners]
        [Asc RepoOwner]
    pure $ nub owners

-- brittany-disable-next-binding

accountsList :: Maybe Text -> [OwnerName] -> Widget
accountsList mDescription owners =
    $(widgetFile "admin/marketplace/accounts-list")
