{-# LANGUAGE QuasiQuotes                #-}
{-# LANGUAGE RecordWildCards            #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE BangPatterns               #-}
{-# LANGUAGE DeriveGeneric              #-}
{-# LANGUAGE DeriveDataTypeable         #-}
{-# LANGUAGE StandaloneDeriving         #-}
{-# LANGUAGE ExistentialQuantification  #-}
{-# LANGUAGE TemplateHaskell            #-}
{-# LANGUAGE OverloadedStrings          #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE DeriveDataTypeable         #-}
{-# LANGUAGE RecordWildCards            #-}
{-# LANGUAGE DeriveGeneric              #-}
{-# LANGUAGE StandaloneDeriving         #-}
{-# LANGUAGE TypeSynonymInstances       #-}
{-# LANGUAGE FlexibleInstances          #-}
{-# OPTIONS_GHC -fno-warn-orphans       #-}
{-# OPTIONS_GHC -fno-warn-unused-binds  #-}



-- | The KeyStore and Associated Types
--
-- Note that most of these types and functions were generated by the
-- api-tools ("Data.Api.Tools") from the schema in "Data.KeyStore.Types.Schema",
-- marked down in <https://github.com/cdornan/keystore/blob/master/schema.md>.

module Data.KeyStore.Types
    ( module Data.KeyStore.Types
    , module Data.KeyStore.Types.NameAndSafeguard
    , module Data.KeyStore.Types.E
    , module Data.KeyStore.Types.UTC
    , PublicKey(..)
    , PrivateKey(..)
    ) where

import qualified Control.Lens                   as L
import qualified Crypto.PBKDF.ByteString        as P
import           Crypto.PubKey.RSA (PublicKey(..), PrivateKey(..))
import           Data.KeyStore.Types.Schema
import           Data.KeyStore.Types.NameAndSafeguard
import           Data.KeyStore.Types.E
import           Data.KeyStore.Types.UTC
import           Data.Aeson
import           Data.API.Tools
import           Data.API.JSON
import           Data.API.Types
import qualified Data.ByteString                as B
import qualified Data.HashMap.Strict            as HM
import           Data.List
import qualified Data.Map                       as Map
import           Data.Ord
import qualified Data.Text                      as T
import           Data.Time
import           Data.String
import qualified Data.Vector                    as V
import           Text.Regex


$(generate                         keystoreSchema)


deriving instance Num Iterations
deriving instance Num Octets


-- | Keystore session context, created at the start of a session and passed
-- to the keystore access functions.

data Pattern =
    Pattern
      { _pat_string :: String
      , _pat_regex  :: Regex
      }

instance Eq Pattern where
    (==) pat pat' = _pat_string pat == _pat_string pat'

instance Show Pattern where
    show pat     = "Pattern " ++ show(_pat_string pat) ++ " <regex>"

instance IsString Pattern where
    fromString s =
        Pattern
            { _pat_string = s
            , _pat_regex  = mkRegex s
            }

pattern :: String -> Pattern
pattern = fromString

inj_pattern :: REP__Pattern -> ParserWithErrs Pattern
inj_pattern (REP__Pattern t) =
    return $
        Pattern
            { _pat_string = s
            , _pat_regex  = mkRegex s
            }
  where
    s = T.unpack t

prj_pattern :: Pattern -> REP__Pattern
prj_pattern = REP__Pattern . T.pack . _pat_string


newtype Settings = Settings { _Settings :: Object }
    deriving (Eq,Show)

inj_settings :: REP__Settings -> ParserWithErrs Settings
inj_settings REP__Settings { _stgs_json = Object hm}
                = return $ Settings hm
inj_settings _  = fail "object expected for settings"

prj_settings :: Settings -> REP__Settings
prj_settings (Settings hm) = REP__Settings { _stgs_json = Object hm }

defaultSettings :: Settings
defaultSettings = mempty


instance Monoid Settings where
  mempty = Settings HM.empty

  mappend (Settings fm_0) (Settings fm_1) =
              Settings $ HM.unionWith cmb fm_0 fm_1
    where
      cmb v0 v1 =
        case (v0,v1) of
          (Array v_0,Array v_1) -> Array $ v_0 V.++ v_1
          _                   -> marker

checkSettingsCollisions :: Settings -> [SettingID]
checkSettingsCollisions (Settings hm) =
              [ SettingID k | (k,v)<-HM.toList hm, v==marker ]

marker :: Value
marker = String "*** Collision * in * Settings ***"


inj_safeguard :: REP__Safeguard -> ParserWithErrs Safeguard
inj_safeguard = return . safeguard . _sg_names

prj_safeguard :: Safeguard -> REP__Safeguard
prj_safeguard = REP__Safeguard . safeguardKeys


inj_name :: REP__Name -> ParserWithErrs Name
inj_name = e2p . name . T.unpack . _REP__Name

prj_name :: Name -> REP__Name
prj_name = REP__Name . T.pack . _name



inj_PublicKey :: REP__PublicKey -> ParserWithErrs PublicKey
inj_PublicKey REP__PublicKey{..} =
    return
        PublicKey
            { public_size = _puk_size
            , public_n    = _puk_n
            , public_e    = _puk_e
            }

prj_PublicKey :: PublicKey -> REP__PublicKey
prj_PublicKey PublicKey{..} =
    REP__PublicKey
        { _puk_size = public_size
        , _puk_n    = public_n
        , _puk_e    = public_e
        }


inj_PrivateKey :: REP__PrivateKey -> ParserWithErrs PrivateKey
inj_PrivateKey REP__PrivateKey{..} =
    return
        PrivateKey
            { private_pub  = _prk_pub
            , private_d    = _prk_d
            , private_p    = _prk_p
            , private_q    = _prk_q
            , private_dP   = _prk_dP
            , private_dQ   = _prk_dQ
            , private_qinv = _prk_qinv
            }

prj_PrivateKey :: PrivateKey -> REP__PrivateKey
prj_PrivateKey PrivateKey{..} =
    REP__PrivateKey
        { _prk_pub  = private_pub
        , _prk_d    = private_d
        , _prk_p    = private_p
        , _prk_q    = private_q
        , _prk_dP   = private_dP
        , _prk_dQ   = private_dQ
        , _prk_qinv = private_qinv
        }


e2p :: E a -> ParserWithErrs a
e2p = either (fail . showReason) return

data Dirctn
    = Encrypting
    | Decrypting
    deriving (Show)


pbkdf :: HashPRF
      -> ClearText
      -> Salt
      -> Iterations
      -> Octets
      -> (B.ByteString->a)
      -> a
pbkdf hp (ClearText dat) (Salt st) (Iterations k) (Octets wd) c =
                                        c $ fn (_Binary dat) (_Binary st) k wd
  where
    fn = case hp of
           PRF_sha1   -> P.sha1PBKDF2
           PRF_sha256 -> P.sha256PBKDF2
           PRF_sha512 -> P.sha512PBKDF2

keyWidth :: Cipher -> Octets
keyWidth aes =
    case aes of
       CPH_aes128   -> Octets 16
       CPH_aes192   -> Octets 24
       CPH_aes256   -> Octets 32

void_ :: Void
void_ = Void 0

map_from_list :: Ord a
              => String
              -> (c->[b])
              -> (b->a)
              -> (a->T.Text)
              -> c
              -> ParserWithErrs (Map.Map a b)
map_from_list ty xl xf xt c =
    case [ xt $ xf b | b:_:_<-obss ] of
      [] -> return $ Map.fromDistinctAscList ps
      ds -> fail $ ty ++ ": " ++ show ds ++ "duplicated"
  where
    ps        = [ (xf b,b) | [b]<-obss ]

    obss      = groupBy same $ sortBy (comparing xf) $ xl c

    same b b' = comparing xf b b' == EQ


$(generateAPITools keystoreSchema
                   [ enumTool
                   , jsonTool'
                   , lensTool
                   ])


instance ToJSON KeyStore where
  toJSON = toJSON . toKeyStore_

instance FromJSON KeyStore where
  parseJSON = fmap fromKeyStore_ . parseJSON

instance FromJSONWithErrs KeyStore where
  parseJSONWithErrs = fmap fromKeyStore_ . parseJSONWithErrs


data KeyStore =
  KeyStore
    { _ks_config :: Configuration
    , _ks_keymap :: KeyMap
    }
  deriving (Show,Eq)

toKeyStore_ :: KeyStore -> KeyStore_
toKeyStore_ KeyStore{..} =
  KeyStore_
    { _z_ks_config = toConfiguration_ _ks_config
    , _z_ks_keymap = toKeyMap_        _ks_keymap
    }

fromKeyStore_ :: KeyStore_ -> KeyStore
fromKeyStore_ KeyStore_{..} =
  KeyStore
    { _ks_config = fromConfiguration_ _z_ks_config
    , _ks_keymap = fromKeyMap_        _z_ks_keymap
    }

emptyKeyStore :: Configuration -> KeyStore
emptyKeyStore cfg =
  KeyStore
      { _ks_config = cfg
      , _ks_keymap = emptyKeyMap
      }


data Configuration =
  Configuration
    { _cfg_settings :: Settings
    , _cfg_triggers :: TriggerMap
    }
  deriving (Show,Eq)

toConfiguration_ :: Configuration -> Configuration_
toConfiguration_ Configuration{..} =
  Configuration_
    { _z_cfg_settings =               _cfg_settings
    , _z_cfg_triggers = toTriggerMap_ _cfg_triggers
    }

fromConfiguration_ :: Configuration_ -> Configuration
fromConfiguration_ Configuration_{..} =
  Configuration
    { _cfg_settings =                 _z_cfg_settings
    , _cfg_triggers = fromTriggerMap_ _z_cfg_triggers
    }

defaultConfiguration :: Settings -> Configuration
defaultConfiguration stgs =
  Configuration
    { _cfg_settings = stgs
    , _cfg_triggers = Map.empty
    }


type TriggerMap = Map.Map TriggerID Trigger

toTriggerMap_ :: TriggerMap -> TriggerMap_
toTriggerMap_ mp = TriggerMap_ $ Map.elems mp

fromTriggerMap_ :: TriggerMap_ -> TriggerMap
fromTriggerMap_ TriggerMap_{..} = Map.fromList
  [ (,) _trg_id trg
    | trg@Trigger{..} <- _z_tmp_map
    ]


type KeyMap = Map.Map Name Key

toKeyMap_ :: KeyMap -> KeyMap_
toKeyMap_ mp = KeyMap_ $
  [ NameKeyAssoc_ nm $ toKey_ ky
    | (nm,ky) <- Map.assocs mp
    ]

fromKeyMap_ :: KeyMap_ -> KeyMap
fromKeyMap_ mp_ = Map.fromList
  [ (_z_nka_name,fromKey_ _z_nka_key)
    | NameKeyAssoc_{..} <- _z_kmp_map mp_
    ]

emptyKeyMap :: KeyMap
emptyKeyMap = Map.empty


data Key =
  Key
    { _key_name          :: Name
    , _key_comment       :: Comment
    , _key_identity      :: Identity
    , _key_is_binary     :: Bool
    , _key_env_var       :: Maybe EnvVar
    , _key_hash          :: Maybe Hash
    , _key_public        :: Maybe PublicKey
    , _key_secret_copies :: EncrypedCopyMap
    , _key_clear_text    :: Maybe ClearText
    , _key_clear_private :: Maybe PrivateKey
    , _key_created_at    :: UTCTime
    }
  deriving (Show,Eq)

toKey_ :: Key -> Key_
toKey_ Key{..} =
  Key_
    { _z_key_name          =                   _key_name
    , _z_key_comment       =                   _key_comment
    , _z_key_identity      =                   _key_identity
    , _z_key_is_binary     =                   _key_is_binary
    , _z_key_env_var       =                   _key_env_var
    , _z_key_hash          =                   _key_hash
    , _z_key_public        =                   _key_public
    , _z_key_secret_copies = toEncrypedCopyMap _key_secret_copies
    , _z_key_clear_text    =                   _key_clear_text
    , _z_key_clear_private =                   _key_clear_private
    , _z_key_created_at    = UTC               _key_created_at
    }

fromKey_ :: Key_ -> Key
fromKey_ Key_{..} =
  Key
    { _key_name          =                     _z_key_name
    , _key_comment       =                     _z_key_comment
    , _key_identity      =                     _z_key_identity
    , _key_is_binary     =                     _z_key_is_binary
    , _key_env_var       =                     _z_key_env_var
    , _key_hash          =                     _z_key_hash
    , _key_public        =                     _z_key_public
    , _key_secret_copies = fromEncrypedCopyMap _z_key_secret_copies
    , _key_clear_text    =                     _z_key_clear_text
    , _key_clear_private =                     _z_key_clear_private
    , _key_created_at    = _UTC                _z_key_created_at
    }


type EncrypedCopyMap = Map.Map Safeguard EncrypedCopy

toEncrypedCopyMap :: EncrypedCopyMap -> EncrypedCopyMap_
toEncrypedCopyMap mp = EncrypedCopyMap_ $ Map.elems mp

fromEncrypedCopyMap :: EncrypedCopyMap_ -> EncrypedCopyMap
fromEncrypedCopyMap EncrypedCopyMap_{..} = Map.fromList
  [ (,) _ec_safeguard ec
    | ec@EncrypedCopy{..} <- _z_ecm_map
    ]


L.makeLenses ''KeyStore
L.makeLenses ''Configuration
L.makeLenses ''Key
