{-# LANGUAGE DeriveDataTypeable         #-}
{-# LANGUAGE FlexibleContexts           #-}
{-# LANGUAGE FlexibleInstances          #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE OverlappingInstances       #-}
{-# LANGUAGE UndecidableInstances       #-}

module Graphics.XHB.Atom
    ( AtomT
    , MonadAtom(..)
    , runAtomT
    ) where

import Control.Applicative (Applicative)
import Control.Monad.IO.Class (MonadIO(..))
import Control.Monad.Reader (ReaderT(..), ask)
import Control.Monad.State (StateT, evalStateT, get, modify)
import Control.Monad.Trans.Class (MonadTrans(..))
import Data.HashMap.Lazy (HashMap)
import Data.Typeable (Typeable)
import Graphics.XHB (Connection, SomeError, ATOM, InternAtom(..))
import qualified Data.HashMap.Lazy as M
import qualified Graphics.XHB as X

type AtomInternalT m = ReaderT Connection (StateT (HashMap String ATOM) m)

newtype AtomT m a = AtomT { unAtomT :: AtomInternalT m a }
    deriving (Applicative, Functor, Monad, MonadIO, Typeable)

instance MonadTrans AtomT where
    lift = AtomT . lift . lift

runAtomT :: Monad m => Connection -> AtomT m a -> m a
runAtomT c = flip evalStateT M.empty . flip runReaderT c . unAtomT

class MonadIO m => MonadAtom m where
    getAtom :: String -> m (Either SomeError ATOM)

instance MonadIO m => MonadAtom (AtomT m) where
    getAtom name = AtomT $ ask >>= \c -> do
        ps <- get
        case M.lookup name ps of
            Just atom -> return (Right atom)
            Nothing -> do
                eatom <- liftIO $ X.internAtom c request >>= X.getReply
                case eatom of
                    Left err   -> return (Left err)
                    Right atom -> do
                        modify $ M.insert name atom
                        return (Right atom)
        where request = MkInternAtom True
                                     (fromIntegral $ length name)
                                     (X.stringToCList name)

instance (MonadAtom m, MonadTrans t, MonadIO (t m)) => MonadAtom (t m) where
    getAtom = lift . getAtom