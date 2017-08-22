module ChocoPie where

import Prelude

import Control.Monad.Eff (Eff, kind Effect)
import Data.Record (get, insert)
import Data.Symbol (class IsSymbol, SProxy(..))
import FRP (FRP)
import FRP.Event (Event, create, subscribe)
import Type.Equality (class TypeEquals, from, to)
import Type.Row (class RowLacks, class RowToList, Cons, Nil, RLProxy(RLProxy), RProxy(RProxy), kind RowList)

runChocoPie :: forall bundleRow driverRow sinkRow sourceRow eff
   . ChocoPieRecord eff sourceRow sinkRow driverRow bundleRow
  => (Record sourceRow -> Record sinkRow)
  -> Record driverRow
  -> Eff
       (frp :: FRP | eff)
       Unit
runChocoPie = chocoPieItUp

class ChocoPieRecord (e :: # Effect)
  (sourceRow :: # Type)
  (sinkRow :: # Type)
  (driverRow :: # Type)
  (bundleRow :: # Type)
  | e -> sourceRow sinkRow driverRow bundleRow e where
  chocoPieItUp ::
       (Record sourceRow -> Record sinkRow)
    -> (Record driverRow)
    -> Eff (frp :: FRP | e) Unit

instance chocoPieRecord ::
  ( RowToList sourceRow sourceList
  , RowToList sinkRow sinkList
  , RowToList driverRow driverList
  , RowToList bundleRow bundleList
  , ChocoPieRowList e sourceList sinkList driverList bundleList
  , MakeSinkProxies e sinkList sinkRow bundleList bundleRow
  , CallDrivers e driverList driverRow bundleList bundleRow sourceList sourceRow
  , ReplicateMany e sinkList sinkRow bundleList bundleRow
  ) => ChocoPieRecord e sourceRow sinkRow driverRow bundleRow where
  chocoPieItUp main drivers = do
    sinkProxies <- makeSinkProxies sinkListP bundleListP sinkRowP
    sources <- callDrivers
      driverListP bundleListP sourceListP
      drivers sinkProxies
    let
      sinks = main sources
    _ <- replicateMany sinkListP bundleListP sinks sinkProxies
    pure unit
    where
      sinkListP = RLProxy :: RLProxy sinkList
      bundleListP = RLProxy :: RLProxy bundleList
      driverListP = RLProxy :: RLProxy driverList
      sourceListP = RLProxy :: RLProxy sourceList
      sinkRowP = RProxy :: RProxy sinkRow

class MakeSinkProxies (e :: # Effect)
  (xs :: RowList) (row :: # Type)
  (bundleList :: RowList) (bundles :: # Type)
  | xs -> row
  , bundleList -> bundles where
  makeSinkProxies ::
       RLProxy xs
    -> RLProxy bundleList
    -> RProxy row
    -> Eff (frp :: FRP | e) (Record bundles)

instance makeSinkProxiesCons ::
  ( IsSymbol name
  , MakeSinkProxies e tail tailRow bundleList bundles'
  , RowLacks name bundles'
  , RowCons name { event :: Event a, push :: a -> Eff (frp :: FRP | e) Unit } bundles' bundles
  ) => MakeSinkProxies e (Cons name (Event a) tail) row bundleList bundles where
  makeSinkProxies _ _ _ = do
    bundle <- create
    rest <- makeSinkProxies
      (RLProxy :: RLProxy tail)
      (RLProxy :: RLProxy bundleList)
      (RProxy :: RProxy tailRow)
    pure $ insert nameP bundle rest
    where
      nameP = SProxy :: SProxy name

instance makeSinkProxiesNil ::
  ( TypeEquals (Record bundle) {}
  ) => MakeSinkProxies e Nil row bundleList bundle where
  makeSinkProxies _ _ _ = pure $ from {}

class CallDrivers (e :: # Effect)
  (driverList :: RowList) (driver :: # Type)
  (bundleList :: RowList) (bundle :: # Type)
  (sourceList :: RowList) (source :: # Type)
  | driverList -> driver bundleList sourceList e
  , bundleList -> bundle driverList sourceList e
  , sourceList -> source driverList bundleList e where
  callDrivers ::
       RLProxy driverList
    -> RLProxy bundleList
    -> RLProxy sourceList
    -> Record driver
    -> Record bundle
    -> Eff (frp :: FRP | e) (Record source)

instance callDriversCons ::
  ( IsSymbol name
  , CallDrivers e
      driverTail driverRow
      bundleTail bundleRow
      sourceTail sourceTailRow
  , TypeEquals bundleton { event :: Event a, push :: a -> Eff (frp :: FRP | e) Unit }
  , TypeEquals driverton (Event a -> Eff (frp :: FRP | e) b)
  , RowCons name driverton trash1 driverRow
  , RowCons name bundleton trash2 bundleRow
  , RowLacks name sourceTailRow
  , RowCons name b sourceTailRow sourceRow
  ) => CallDrivers e
    (Cons name driverton driverTail) driverRow
    (Cons name bundleton bundleTail) bundleRow
    (Cons name b sourceTail) sourceRow where
  callDrivers _ _ _ drivers bundles = do
    rest <- callDrivers
      (RLProxy :: RLProxy driverTail)
      (RLProxy :: RLProxy bundleTail)
      (RLProxy :: RLProxy sourceTail)
      drivers
      bundles
    source <- getSource
    pure $ insert nameP source rest :: Record sourceRow
    where
      nameP = SProxy :: SProxy name
      bundleton :: { event :: Event a, push :: a -> Eff (frp :: FRP | e) Unit }
      bundleton = to $ get nameP bundles
      event :: Event a
      event = bundleton.event
      driver :: (Event a -> Eff (frp :: FRP | e) b)
      driver = to $ get nameP drivers
      getSource :: Eff (frp :: FRP | e) b
      getSource = to $ driver event

instance callDriversNil ::
  ( TypeEquals (Record source) {}
  ) => CallDrivers e Nil driver Nil bundle Nil source where
  callDrivers _ _ _ _ _ = pure $ from {}

class ReplicateMany (e :: # Effect)
  (sinkList :: RowList) (sinkRow :: # Type)
  (bundleList :: RowList) (bundleRow :: # Type)
  | sinkList -> sinkRow e
  , bundleList -> bundleRow e where
  replicateMany ::
       RLProxy sinkList
    -> RLProxy bundleList
    -> Record sinkRow
    -> Record bundleRow
    -> Eff (frp :: FRP | e) Unit

instance replicateManyCons ::
  ( IsSymbol name
  , TypeEquals bundleton { event :: Event a, push :: a -> Eff (frp :: FRP | e) Unit}
  , RowCons name (Event a) sinkTailRow sinkRow
  , RowCons name bundleton bundleTailRow bundleRow
  , ReplicateMany e sinkTail sinkRow bundleTail bundleRow
  ) => ReplicateMany e
    (Cons name (Event a) sinkTail) sinkRow
    (Cons name bundleton bundleTail) bundleRow where
  replicateMany _ _ sinks bundles = do
    subscribe sink bundle.push
    replicateMany sinkTailRowP bundleTailRowP sinks bundles
    where
      nameP = SProxy :: SProxy name
      sink = get nameP sinks
      bundle :: { event :: Event a, push :: a -> Eff (frp :: FRP | e) Unit}
      bundle = to $ get nameP bundles
      sinkTailRowP = RLProxy :: RLProxy sinkTail
      bundleTailRowP = RLProxy :: RLProxy bundleTail

instance replicateManyNil :: ReplicateMany e Nil sinkRow Nil bundleRow where
  replicateMany _ _ _ _ = pure unit

class ChocoPieRowList (e :: # Effect)
  (sourceList :: RowList)
  (sinkList :: RowList)
  (driverList :: RowList)
  (bundleList :: RowList)
  | sourceList -> sinkList driverList bundleList e
  , sinkList -> sourceList driverList bundleList e
  , driverList -> sourceList sinkList bundleList e
  , bundleList -> sourceList sinkList driverList e

instance chocoPieRowListCons ::
  ( ChocoPieRowList e sourceTail sinkTail driverTail bundleTail
  , TypeEquals driver ((Event a) -> Eff (frp :: FRP | e) b)
  , TypeEquals c { event :: Event a, push :: a -> Eff (frp :: FRP | e) Unit}
  ) => ChocoPieRowList e
    (Cons k b sourceTail)
    (Cons k (Event a) sinkTail)
    (Cons k driver driverTail)
    (Cons k c bundleTail)

instance chocoPieRowListNil :: ChocoPieRowList e Nil Nil Nil Nil
