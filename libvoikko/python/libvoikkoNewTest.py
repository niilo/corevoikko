# -*- coding: utf-8 -*-

# Copyright 2009 - 2010 Harri Pitkänen (hatapitk@iki.fi)
# Test suite for testing public API of libvoikko and the Python interface.

# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA

import unittest
from libvoikkoNew import *

class LibvoikkoTest(unittest.TestCase):
	def setUp(self):
		self.voikko = Voikko()
	
	def tearDown(self):
		self.voikko.terminate()
	
	def testInitAndTerminate(self):
		pass # do nothing, just check that setUp and tearDown complete succesfully
	
	def testTerminateCanBeCalledMultipleTimes(self):
		self.voikko.terminate()
		self.voikko.terminate()
	
	def testAnotherObjectCanBeCreatedUsedAndDeletedInParallel(self):
		medicalVoikko = Voikko(variant = "medicine")
		self.failUnless(medicalVoikko.spell(u"amifostiini"))
		self.failIf(self.voikko.spell(u"amifostiini"))
		del medicalVoikko
		self.failIf(self.voikko.spell(u"amifostiini"))
	
	def testDictionaryComparisonWorks(self):
		d1 = Dictionary("a", u"b")
		d2 = Dictionary("a", u"c")
		d3 = Dictionary("c", u"b")
		d4 = Dictionary("a", u"b")
		self.assertNotEqual(u"kissa", d1)
		self.assertNotEqual(d1, u"kissa")
		self.assertNotEqual(d1, d2)
		self.assertNotEqual(d1, d3)
		self.assertEqual(d1, d4)
		self.failUnless(d1 < d2)
		self.failUnless(d2 < d3)
	
	def testDictionaryHashCodeWorks(self):
		d1 = Dictionary("a", u"b")
		d2 = Dictionary("a", u"c")
		d3 = Dictionary("c", u"b")
		d4 = Dictionary("a", u"b")
		self.assertNotEqual(hash(d1), hash(d2))
		self.assertNotEqual(hash(d1), hash(d3))
		self.assertEqual(hash(d1), hash(d4))
	
	def testInitWithCorrectDictWorks(self):
		self.voikko.terminate()
		self.voikko = Voikko(variant = "standard")
		self.failIf(self.voikko.spell(u"amifostiini"))
		self.voikko.terminate()
		self.voikko = Voikko(variant = "medicine")
		self.failUnless(self.voikko.spell(u"amifostiini"))
	
	def testInitWithNonExistentDictThrowsException(self):
		def tryInit():
			self.voikko = Voikko(variant = "nonexistentvariant")
		self.voikko.terminate()
		self.assertRaises(VoikkoException, tryInit)
	
	def testInitWithCacheSizeWorks(self):
		# TODO: better test
		self.voikko.terminate()
		self.voikko = Voikko(cacheSize = 3)
		self.failUnless(self.voikko.spell(u"kissa"))
	
	def testInitWithPathWorks(self):
		# TODO: better test
		self.voikko.terminate()
		self.voikko = Voikko(path = "/path/to/nowhere")
		self.failUnless(self.voikko.spell(u"kissa"))
	
	def testSpellAfterTerminateThrowsException(self):
		def trySpell():
			self.voikko.spell(u"kissa")
		self.voikko.terminate()
		self.assertRaises(VoikkoException, trySpell)
	
	def testSpell(self):
		self.failUnless(self.voikko.spell(u"määrä"))
		self.failIf(self.voikko.spell(u"määä"))
	
	def testSuggest(self):
		suggs = self.voikko.suggest(u"koirra")
		self.failUnless(u"koira" in suggs)
	
	def testSuggestReturnsArgumentIfWordIsCorrect(self):
		suggs = self.voikko.suggest(u"koira")
		self.assertEqual(1, len(suggs))
		self.assertEqual(u"koira", suggs[0])
	
	def testSetIgnoreDot(self):
		self.voikko.setIgnoreDot(False)
		self.failIf(self.voikko.spell(u"kissa."))
		self.voikko.setIgnoreDot(True)
		self.failUnless(self.voikko.spell(u"kissa."))
	
	def testSetIgnoreNumbers(self):
		self.voikko.setIgnoreNumbers(False)
		self.failIf(self.voikko.spell(u"kissa2"))
		self.voikko.setIgnoreNumbers(True)
		self.failUnless(self.voikko.spell(u"kissa2"))
	
	def testSetIgnoreUppercase(self):
		self.voikko.setIgnoreUppercase(False)
		self.failIf(self.voikko.spell(u"KAAAA"))
		self.voikko.setIgnoreUppercase(True)
		self.failUnless(self.voikko.spell(u"KAAAA"))
	
	def testAcceptFirstUppercase(self):
		self.voikko.setAcceptFirstUppercase(False)
		self.failIf(self.voikko.spell("Kissa"))
		self.voikko.setAcceptFirstUppercase(True)
		self.failUnless(self.voikko.spell("Kissa"))
	
	def testUpperCaseScandinavianLetters(self):
		self.failUnless(self.voikko.spell(u"Äiti"))
		self.failIf(self.voikko.spell(u"Ääiti"))
		self.failUnless(self.voikko.spell(u"š"))
		self.failUnless(self.voikko.spell(u"Š"))
	
	def testAcceptAllUppercase(self):
		self.voikko.setIgnoreUppercase(False)
		self.voikko.setAcceptAllUppercase(False)
		self.failIf(self.voikko.spell("KISSA"))
		self.voikko.setAcceptAllUppercase(True)
		self.failUnless(self.voikko.spell("KISSA"))
		self.failIf(self.voikko.spell("KAAAA"))
	
	def testIgnoreNonwords(self):
		self.voikko.setIgnoreNonwords(False)
		self.failIf(self.voikko.spell("hatapitk@iki.fi"))
		self.voikko.setIgnoreNonwords(True)
		self.failUnless(self.voikko.spell("hatapitk@iki.fi"))
		self.failIf(self.voikko.spell("ashdaksd"))
	
	def testAcceptExtraHyphens(self):
		self.voikko.setAcceptExtraHyphens(False)
		self.failIf(self.voikko.spell("kerros-talo"))
		self.voikko.setAcceptExtraHyphens(True)
		self.failUnless(self.voikko.spell("kerros-talo"))
	
	def testAcceptMissingHyphens(self):
		self.voikko.setAcceptMissingHyphens(False)
		self.failIf(self.voikko.spell("sosiaali"))
		self.voikko.setAcceptMissingHyphens(True)
		self.failUnless(self.voikko.spell("sosiaali"))
	
	def TODOtestSetAcceptTitlesInGc(self):
		self.voikko.setAcceptTitlesInGc(False)
		self.assertEqual(1, len(self.voikko.grammarErrors(u"Kissa on eläin")))
		self.voikko.setAcceptTitlesInGc(True)
		self.assertEqual(0, len(self.voikko.grammarErrors(u"Kissa on eläin")))
	
	def TODOtestSetAcceptUnfinishedParagraphsInGc(self):
		self.voikko.setAcceptUnfinishedParagraphsInGc(False)
		self.assertEqual(1, len(self.voikko.grammarErrors(u"Kissa on ")))
		self.voikko.setAcceptUnfinishedParagraphsInGc(True)
		self.assertEqual(0, len(self.voikko.grammarErrors(u"Kissa on ")))
	
	def TODOtestSetAcceptBulletedListsInGc(self):
		self.voikko.setAcceptBulletedListsInGc(False)
		self.assertNotEqual(0, len(self.voikko.grammarErrors(u"kissa")))
		self.voikko.setAcceptBulletedListsInGc(True)
		self.assertEqual(0, len(self.voikko.grammarErrors(u"kissa")))
	
	def TODOtestSetNoUglyHyphenation(self):
		self.voikko.setNoUglyHyphenation(False)
		self.assertEqual(u"i-va", self.voikko.hyphenate(u"iva"))
		self.voikko.setNoUglyHyphenation(True)
		self.assertEqual(u"iva", self.voikko.hyphenate(u"iva"))
	
	def TODOtestSetHyphenateUnknownWordsWorks(self):
		self.voikko.setHyphenateUnknownWords(False)
		self.assertEqual(u"kirjutepo", self.voikko.hyphenate(u"kirjutepo"))
		self.voikko.setHyphenateUnknownWords(True)
		self.assertEqual(u"kir-ju-te-po", self.voikko.hyphenate(u"kirjutepo"))
	
	def TODOtestSetMinHyphenatedWordLength(self):
		self.voikko.setMinHyphenatedWordLength(6)
		self.assertEqual(u"koira", self.voikko.hyphenate(u"koira"))
		self.voikko.setMinHyphenatedWordLength(2)
		self.assertEqual(u"koi-ra", self.voikko.hyphenate(u"koira"))
	
	def testSetSuggestionStrategy(self):
		self.voikko.setSuggestionStrategy(SuggestionStrategy.OCR)
		self.failIf(u"koira" in self.voikko.suggest(u"koari"))
		self.failUnless(u"koira" in self.voikko.suggest(u"koir_"))
		self.voikko.setSuggestionStrategy(SuggestionStrategy.TYPO)
		self.failUnless(u"koira" in self.voikko.suggest(u"koari"))

if __name__ == "__main__":
	suite = unittest.TestLoader().loadTestsFromTestCase(LibvoikkoTest)
	unittest.TextTestRunner(verbosity=1).run(suite)
