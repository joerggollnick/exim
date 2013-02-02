#!/usr/bin/env python2

# Copyright (c) 2011 Laurent Ghigonis <laurent@gouloum.fr>
#           (c) 2012 Joerg Gollnick <mail2phone@wurzelbenutzer.de>
#
# Permission to use, copy, modify, and distribute this software for any
# purpose with or without fee is hereby granted, provided that the above
# copyright notice and this permission notice appear in all copies.
#
# THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
# WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
# ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
# WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
# ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
# OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

import sys, os, string, re
import pjsua as pj
#import logging
import time

def log_cb(level, str, len):
    print str,

class acc_cb(pj.AccountCallback):
    def __init__(self, account=None):
        pj.AccountCallback.__init__(self, account)
        
    def on_reg_state(self):
        global current_account
        if self.account.info().reg_active:
            print "Account id ",  self.account.info().uri
            current_account = self.account
        
class call_cb(pj.CallCallback):
    def __init__(self, call=None):
        pj.CallCallback.__init__(self, call)

    def on_state(self):
	global current_call
        global player
        global lib

        print "Call is ", self.call.info().state_text,
        print "last code =", self.call.info().last_code, 
        print "(" + self.call.info().last_reason + ")",
        print "Media is ", self.call.info().media_state

	if self.call.info().state == pj.CallState.DISCONNECTED:
	    current_call = None
            lib.player_destroy( player )
            player = None
        
                
    def on_media_state(self):
        global lib
        global wavfile
        global player
        print "Media is ", self.call.info().media_state

        if self.call.info().media_state == pj.MediaState.ACTIVE:
            try:

                print "Call is ", self.call.info().state_text,
                print "last code =", self.call.info().last_code, 
                print "(" + self.call.info().last_reason + ")"
                if self.call.info().state == pj.CallState.CONFIRMED:
                    call_slot = self.call.info().conf_slot
                    lib.player_set_pos( player, 0 )
                    play_slot = lib.player_get_slot(player)
                    lib.conf_connect(play_slot, call_slot)

            except pj.Error, e:
                print "Sentence not sent !!! Exception " + str(e)
                player = None

    def on_dtmf_digit(self,digit):
        global result
        global dtmf

        print "Received dtmf code:", digit
        if digit == dtmf:
            print "Accepted"
            result = int(digit)
            self.call.hangup()

            
# main
if len(sys.argv) < 3:
    print 'usage: sendwav2phone <destination> <myfile> <dtmf> [mydomain mylogin mypass]'
    print '   destination is an URI to call, e.g. [sip:][extension@]ip'
    print '     specify login credentials if you want to register'
    sys.exit(1)

# first argument destination
if string.find(sys.argv[1], "sip:", 0) == 0:
    dest = sys.argv[1]
else:
# add sip: if ommited
    dest = "sip:"+sys.argv[1]

# filename to play
global wavfile
wavfile = sys.argv[2]

# dtmf code for acceptence
global dtmf
dtmf = sys.argv[3]

# optional credentials
if len(sys.argv) > 4:
    auth = True
    auth_domain = sys.argv[4]
    auth_login = sys.argv[5]
    if len(sys.argv) > 6:
        auth_pass = sys.argv[6]
    else:
        auth_pass = ""
else:
    auth = False

try:
    global current_account
    global current_call
    global player
    global result

    # library 
    mc  = pj.MediaConfig()
    mc.clock_rate = 16000
    lib = pj.Lib()
    lib.init(log_cfg = pj.LogConfig(level=0, callback=log_cb),media_cfg=mc)
    # no sound device 
    lib.set_null_snd_dev()
    lib.set_codec_priority('G722/16000/1', 0 )

    # no account active
    current_account = None
    # no call active
    current_call = None
    # nothing to play
    player = None
    # result 
    result = 10
    # start library
    lib.start()
    # create transport
    transport = lib.create_transport(pj.TransportType.UDP)

    if auth:
        acc_cfg = pj.AccountConfig()
        acc_cfg.id = 'sip:' + auth_login + '@' + auth_domain 
        acc_cfg.reg_uri = 'sip:' + auth_domain
        acc_cfg.proxy = [ 'sip:' + auth_domain + ';lr' ]
        acc_cfg.auth_cred = [ pj.AuthCred("*", auth_login, auth_pass) ]

        acc = lib.create_account(acc_cfg, cb=acc_cb())
        acc.set_transport(transport)
    else:
	acc = lib.create_account_for_transport(transport)

    # wait until account is registered
    while current_account == None:
        time.sleep( 1 )

    if player != None:
        lib.player_destroy( player )
        player = None

    if player == None:
        player = lib.create_player(wavfile, True)

    # call out
    current_call = acc.make_call(dest, call_cb())

    # wait until call is disconnected
    while current_call != None:
      if current_call.info().call_time > 50:
	current_call.hangup()

      time.sleep( 1 )

    transport = None

    if dtmf == 'N':
      print "Accepted"

    # Account
    acc.delete()
    acc = None
    # Library 
    lib.destroy()
    lib = None

    exit(0)

except pj.Error, e:
    print "Exception: " + str(e)
    lib.destroy()
    lib = None
    exit(255)

