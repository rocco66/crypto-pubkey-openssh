{-# LANGUAGE OverloadedStrings #-}

module Crypto.PubKey.OpenSsh.Encode where

import Control.Monad (when)
import Data.ByteString.Char8 (ByteString)
import Data.Bits (testBit)
import Data.List (unfoldr)
import Data.Word (Word8)
import qualified Data.ByteString as BS

import Data.Serialize (Put, Putter, runPut, putByteString, putWord32be, put)
import qualified Crypto.Types.PubKey.DSA as DSA
import qualified Crypto.Types.PubKey.RSA as RSA
import qualified Data.ByteString.Base64 as Base64

import Crypto.PubKey.OpenSsh.Types (OpenSshPublicKeyType(..),
                                    OpenSshPublicKey(..))

fixZeroByte :: [Word8] -> [Word8]
fixZeroByte bs = if testBit (head bs) msb then 0:bs else bs
  where
    msb = 7

expandInteger :: Integer -> [Word8]
expandInteger n = reverse $ unfoldr expand $ n
  where
    expand :: Integer -> Maybe (Word8, Integer)
    expand e | e == 0    = Nothing
             | otherwise = Just $ getResults $ quotRem e 256
    getResults :: (Integer, Integer) -> (Word8, Integer)
    getResults (i, w) = (fromIntegral w, i)

keyTypePutter :: Putter OpenSshPublicKeyType
keyTypePutter OpenSshPublicKeyTypeRsa = putByteString "ssh-rsa"
keyTypePutter OpenSshPublicKeyTypeDsa = putByteString "ssh-dss"

mpint :: Integer -> ByteString
mpint i = runPut $ do
    putWord32be $ fromIntegral $ length binary
    mapM_ put binary
  where
    binary = fixZeroByte $ expandInteger i

commonPublicKeyPutter :: OpenSshPublicKeyType
                      -> ByteString
                      -> ByteString
                      -> Put
commonPublicKeyPutter keyType comment body = do
    keyTypePutter keyType
    putByteString " "
    putByteString $ Base64.encode $ BS.append wrapType body
    when (not $ BS.null comment) $ do
        putByteString " "
        putByteString comment
  where
    binaryType = runPut $ keyTypePutter keyType
    wrapType = runPut $ do
        putWord32be $ fromIntegral $ BS.length $ binaryType
        putByteString binaryType

openSshPublicKeyPutter :: Putter OpenSshPublicKey
openSshPublicKeyPutter (OpenSshPublicKeyRsa
                        (RSA.PublicKey _ public_n public_e)
                        comment) =
    commonPublicKeyPutter OpenSshPublicKeyTypeRsa comment $ BS.concat
        [ mpint public_e
        , mpint public_n ]

openSshPublicKeyPutter (OpenSshPublicKeyDsa
                        (DSA.PublicKey (public_p, public_g, public_q) public_y)
                        comment) =
    commonPublicKeyPutter OpenSshPublicKeyTypeDsa comment $ BS.concat
        [ mpint public_p
        , mpint public_q
        , mpint public_g
        , mpint public_y ]

encode :: OpenSshPublicKey -> ByteString
encode = runPut . openSshPublicKeyPutter
