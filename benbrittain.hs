{-# LANGUAGE DeriveDataTypeable, OverloadedStrings, Arrows #-}
module Main where

import Prelude hiding (id)
import Control.Arrow ((>>>), arr, (&&&), (>>^))
import Control.Category (id)
import Control.Monad (forM_)
import Data.Monoid (mempty, mconcat)
import Data.List (isInfixOf, sortBy)
import Data.Ord (comparing)
import Text.Pandoc (Pandoc, HTMLMathMethod(..), WriterOptions(..), 
                    defaultWriterOptions, ParserState)
import Text.Pandoc.Shared (ObfuscationMethod(..))
import System.Directory 
import Data.Time.Format (parseTime, formatTime)
import System.FilePath (joinPath, splitDirectories, takeDirectory)
import Text.Blaze.Html.Renderer.String (renderHtml)
import Text.Blaze.Internal (preEscapedString)
import Text.Blaze ((!), toValue)
import qualified Text.Blaze.Html5 as H
import qualified Text.Blaze.Html5.Attributes as A
import qualified Data.ByteString.Char8 as B

import Hakyll hiding (chronological)


articlesPerIndexPage :: Int
articlesPerIndexPage = 5 


main :: IO ()
main = hakyllWith config $ do
    -- gotta have a favicon
    match "favicon.ico" $ do
        route   idRoute
        compile copyFileCompiler

    match "about.html" $ do
      route $ setExtension ".html"
      compile $ pageCompiler
          >>> addPageTitle
          >>> applyTemplateCompiler "templates/default.html"
          >>> relativizeUrlsCompiler

    -- Read templates.
    match "templates/*" $ compile templateCompiler
    
    -- Compress CSS files.
    match "css/*" $ do
        route   idRoute
        compile compressCssCompiler

    -- Render simple posts.
    forM_ ["*.markdown", "*.lhs"] $ 
      \p -> match (parseGlob ("posts/*/*/" ++ p)) $ do
        route   $ setExtension ".html"
        compile $ pageCompiler
            >>> addPageDate
            >>> addPageTitle 
            >>> arr (copyBodyToField "post")
            >>> applyTemplateCompiler "templates/post.html"
            >>> applyTemplateCompiler "templates/default.html"
            >>> arr (copyBodyToField "description")
            >>> relativizeUrlsCompiler


    -- resources and stuff
    forM_ [ "files/*", "images/*" ] $
      \p -> match p $ do
        route   idRoute
        compile copyFileCompiler

    -- Generate index pages
    match "index*.html" $ route idRoute
    metaCompile $ requireAll_ postsPattern
      >>> arr (chunk articlesPerIndexPage . chronological)
      >>^ makeIndexPages

    match "404.html" $ do
        route idRoute
        compile $ readPageCompiler
            >>> applyTemplateCompiler "templates/default.html"
  where
    postsPattern :: Pattern (Page String)
    postsPattern = predicate (\i -> matches "posts/*/*/*.markdown" i)
                   
-- | Add a page date field.
addPageDate :: Compiler (Page String) (Page String)
addPageDate = (arr (getField "date") &&& id)
               >>> arr (uncurry $ (setField "date") . ("" ++))


-- | Add a page title field.
addPageTitle :: Compiler (Page String) (Page String)
addPageTitle = (arr (getField "title") &&& id)
               >>> arr (uncurry $ (setField "pagetitle") . ("Ben Brittain | " ++))

-- | Auxiliary compiler: generate a post list from a list of given posts, and
-- add it to the current page under @$posts@.
addPostList :: String -> Compiler (Page String, [Page String]) (Page String)
addPostList tmp = setFieldA "posts" $
    arr chronological
        >>> require (parseIdentifier tmp) (\p t -> map (applyTemplate t) p)
        >>> arr mconcat >>> arr pageBody


-- | Helper function for index page metacompilation: generate
-- appropriate number of index pages with correct names and the
-- appropriate posts on each one.
makeIndexPages :: [[Page String]] -> 
                  [(Identifier (Page String), Compiler () (Page String))]
makeIndexPages ps = map doOne (zip [1..] ps)
  where doOne (n, ps) = (indexIdentifier n, makeIndexPage n maxn ps)
        maxn = nposts `div` articlesPerIndexPage +
               if (nposts `mod` articlesPerIndexPage /= 0) then 1 else 0
        nposts = sum $ map length ps
        indexIdentifier n = parseIdentifier url
          where url = "index" ++ (if (n == 1) then "" else show n) ++ ".html" 


-- Make a single index page: inserts posts, sets up navigation links
-- to older and newer article index pages, applies templates.
makeIndexPage :: Int -> Int -> [Page String] -> Compiler () (Page String)
makeIndexPage n maxn posts = 
    constA (mempty, posts)
    >>> addPostList "templates/postitem.html"
    >>> arr (setField "navlinkolder" (indexNavLink n 1 maxn))
    >>> arr (setField "navlinknewer" (indexNavLink n (-1) maxn))
    >>> arr (setField "pagetitle" "Ben Brittain")
    >>> applyTemplateCompiler "templates/post.html"
    >>> applyTemplateCompiler "templates/index.html"
    >>> applyTemplateCompiler "templates/default.html"
    >>> relativizeUrlsCompiler


-- Generate navigation link HTML for stepping between index pages.
indexNavLink :: Int -> Int -> Int -> String
indexNavLink n d maxn = renderHtml ref
  where ref = if (refPage == "") then ""
              else H.a ! A.href (toValue $ toUrl $ refPage) $ 
                   (preEscapedString lab)
        lab = if (d > 0) then "&laquo; Older Posts" else "Newer Posts &raquo;"
        refPage = if (n + d < 1 || n + d > maxn) then ""
                  else case (n + d) of
                    1 -> "index.html"
                    _ -> "index" ++ (show $ n + d) ++ ".html"
  
-- Sort pages chronologically.
chronological :: [Page String] -> [Page String]
chronological = reverse . (sortBy $ comparing pageSortKey)


-- Generate a sort key for ordering entries on the index page.
pageSortKey :: Page String -> String
pageSortKey pg =  datePart
  where path = getField "path" pg
        datePart = joinPath $ take 3 $ drop 1 $ splitDirectories path


-- Split list into equal sized sublists.
chunk :: Int -> [a] -> [[a]]
chunk n [] = []
chunk n xs = ys : chunk n zs
    where (ys,zs) = splitAt n xs


config :: HakyllConfiguration
config = defaultHakyllConfiguration 
    { deployCommand =   "rsync -ave 'ssh' \
                        \_site/* bbrittain_benbrittain@ssh.phx.nearlyfreespeech.net:/home/public"
    }
