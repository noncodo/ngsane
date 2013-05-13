#!/bin/python
######################################
# Generate contact maps from bam files 
# and fragment lists
#
# Author: Fabian Buske (13/05/2013)
######################################


import os
import sys
import traceback
from optparse import OptionParser
import pysam
from quicksect import IntervalTree
import fileinput
import datetime

######################################
# Read
######################################

class Read():
    def __init__(self, read):
        if (read==""):
            self.seq=""
            self.qname="dummy"
            self.is_unmapped=True
            self.tid=None
            self.is_read1=None
            self.is_reverse=None
        else:
            self.is_duplicate=read.is_duplicate
            self.is_unmapped=read.is_unmapped
            self.tid=read.tid
            self.qname=read.qname
            self.is_read1=True
            if (read.is_read2):
                self.is_read1=False
            self.is_reverse=read.is_reverse
            self.alen=read.alen
            self.pos=read.pos

    def check(self):
        if(self.is_reverse):
            self.revcomp()

    def isPair(self,number):
        if(self.is_read1 and number==0):
            return True
        if(not(self.is_read1) and number==1):
            return True
        print("Reads not paired up correctly: paired/single ended? not namesorted?")
        print(str(self)+" "+str(number))

    def __str__(self): 
        if(self.is_unmapped):
            return "%s read1 %s %s" % (self.qname,self.is_read1,self.seq)
        else:
            return "%s read1 %s %s %i %i" % (self.qname,self.is_read1, self.tid,self.pos,self.alen)

    def revcomp(self):
        basecomplement = {'N':'N','A': 'T', 'C': 'G', 'G': 'C', 'T': 'A'}
        rc=""
        for i in reversed(self.seq):
            rc+=basecomplement[i]
        self.seq=rc


    def getInfo(self, string):
        for i in self.tags:
            if( i[0]==string):
                return i[1]

######################################
# Interval
######################################
class Interval():
	def __init__(self, chrom, start, end):
		self.chrom=chrom
		self.start=start
		self.end=end

######################################
# Timestamp
######################################
def timeStamp():
    return datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S').format()


# manage option and arguments processing
def main():
	global options
	global args
	usage = '''usage: %prog [options] bamFile

generates (single locus) fragmentCounts and (pairwise) contactCount files
	'''
	parser = OptionParser(usage)
	parser.add_option("-q", "--quiet", action="store_false", dest="verbose", default=True,
					help="don't print status messages to stdout")
	parser.add_option("-v", "--verbose", action="store_true", dest="verbose", default=False,
					help="print status messages to stdout")
	parser.add_option("-V", "--veryverbose", action="store_true", dest="vverbose", default=False,
					help="print lots of status messages to stdout")
	parser.add_option("-g", "--genomeFragmentFile", type="string", dest="fragmentFile", default="", 
					help="file containing the genome fragments after digestion with the restriction enzyme(s), generated by hicup")
	parser.add_option("-f", "--fragmentAggregation", type="int", dest="fragmentAggregation", default=10, 
					help="number of restriction enzyme fragments to concat")
#	parser.add_option("-s", "--fragmentSize", type="int", dest="fragmentSize", default=50000, 
#					help="size of a fragment in bp if no genomeFragmentFile is given")
	parser.add_option("-o", "--outputDir", type="string", dest="outputDir", default="", 
					help="output directory [default: %default]")
	parser.add_option("-t", "--tmpDir", type="string", dest="tmpDir", default="/tmp", 
					help="directory for temp files [default: %default]")

	(options, args) = parser.parse_args()
	if (len(args) < 1):
		parser.print_help()
		parser.error("[ERROR] Incorrect number of arguments, need a dataset")
	
	if (options.fragmentAggregation < 1):
		parser.error("[ERROR] fragmentAggregation must be a positive integer, was :"+str(options.fragmentAggregation))
		sys.exit(1)

#	if (options. fragmentSize < 1):
#		parser.error("[ERROR] fragmentSize must be a positive integer, was :"+str(options.fragmentSize))
#		sys.exit(1)
		
	if (options.outputDir != ""): 
		options.outputDir += os.sep

	if (options.verbose):
		print >> sys.stdout, "fragmentFile:          %s" % (options. fragmentFile)
		print >> sys.stdout, "fragmentAggregation:   %s" % (options. fragmentAggregation)
#		print >> sys.stdout, "fragmentSize:          %s" % (options. fragmentSize)
		print >> sys.stdout, "outputDir:             %s" % (options.outputDir)
		print >> sys.stdout, "tmpDir:                %s" % (options.tmpDir)

	process()

def createIntervalTrees():
	''' 
		creates one interval tree for quick lookups
		returns 
			fragmentsMap[fragmentId] = [tuple(chrom, fragmentMidPoint)]
			intersect_tree - intersect Tree for interval matching
		
	'''
	
	if (options.verbose):
		print >> sys.stdout, "- %s START   : populate intervaltree from fragmented genome" % (timeStamp())

	intersect_tree = IntervalTree()
	fragmentsCount = 0
	fragmentsMap = {}
	
	start = 0
	end = 0
	counter = 0
	chrom = ""
	
	for line in fileinput.input([options.fragmentFile]):
		line = line.strip()
		if (len(line)==0 or line.startswith("Genome") or line.startswith("Chromosome")):
			continue
			
		cols = line.split("\t")
		try:
			# check if chromosome changed from last
			if (cols[0] != chrom):
				# do we have do finish the last chromosome?
				if (end > 0):
					interval = Interval(chrom, start, end)
					intersect_tree.insert(interval, fragmentsCount)
					fragmentsMap[fragmentsCount] = tuple([chrom, end-start])
					fragmentsCount += 1
					if (options.vverbose):
						print >> sys.stdout,  "-- intervaltree.add %s:%d-%d" % (chrom, start, end)
				chrom = cols[0]
				start = int(cols[1])
				end = int(cols[2])
				counter = 0

			# check if fragement aggregation is fulfilled
			elif (counter >= options.fragmentAggregation):
				interval = Interval(chrom, start, end)
				intersect_tree.insert(interval, fragmentsCount)
				if (options.vverbose):
					print >> sys.stdout,  "-- intervaltree.add %s:%d-%d" % (chrom, start, end)

				fragmentsMap[fragmentsCount] = tuple([chrom, end-start])
				start = int(cols[1])
				end = int(cols[2])
				counter = 0
				fragmentsCount += 1				
			else:
				end = int(cols[2])
				
			# increment counter
			counter += 1
		
		except:
			if (options.verbose):
				print >> sys.stderr, 'skipping line in options.fragmentFile: %s' % (line)
			if (options.vverbose):
				traceback.print_exc()
	
	
	# handle last fragment
	if (end > 0):
		interval = Interval(chrom, start, end)
		intersect_tree.insert(interval, fragmentsCount)
		fragmentsMap[fragmentsCount] = tuple([chrom, int(0.5*(start+end))])
		fragmentsCount += 1
		if (options.vverbose):
			print >> sys.stdout, "-- intervaltree.add %s:%d-%d" % (chrom, start, end)
	
	if (options.verbose):
		print >> sys.stdout, "- %s FINISHED: intervaltree populated" % (timeStamp())
			
	return [fragmentsMap, intersect_tree]

def getNext(iterator):
	''' 
	get the next read and populate object
	'''
	
	try:
		return Read(iterator.next())
	except StopIteration:
		if (options.vverbose):
			traceback.print_exc()
		return Read("")
		
        
def findNextReadPair(samiter):
	''' 
	find the next read pair
	'''
	readpair=[getNext(samiter), getNext(samiter)]
	
	while(readpair[0].qname!= readpair[1].qname):
		if (args.v):
			print "[WARN] File: drop first from unpaired read %s %s" %(readpair[0].qname, readpair[1].qname)
		readpair.pop(0)
		readpair.append(getNext(arr1))
		
	return readpair
   
def find(interval, tree):
    ''' Returns a list with the overlapping intervals '''
    out = []
    tree.intersect( interval, lambda x: out.append(x) )
    return [ (x.start, x.end, x.linenum) for x in out ]
          

def getFragment(samfile, read, intersect_tree, fragmentList):
	fragmentID = -1
	try:
		# get fragments for both reads
		interval = Interval(samfile.getrname(read.tid), read.pos, read.pos+read.alen)

		fragments = find(interval, intersect_tree)
		if (len(fragments) == 0 ):
			if (options.vverbose):
				print >> sys.stderr, '[WARN] no overlap found : %s (skipping)' % (read)	
			return
		elif (len(fragments)> 1):
			if (options.vverbose):
				print >> sys.stderr, '[WARN] number of fragments > 1 : %s (skipping)' % (read)	
		
		#extract fragmentID
		fragmentID = fragments[0][2] # corresponds to linenum
		
		if (not fragmentList.has_key(fragmentID)):
			fragmentList[fragmentID] = 0

		fragmentList[fragmentID] += 1
		
	except:
		if (options.verbose):
			print >> sys.stderr, '[WARN] problems with interval intersection: %s (skipping)' % (read)		
			traceback.print_exc()
			sys.exit(1)
		if (options.vverbose):
			traceback.print_exc()
			
	return fragmentID

def countReadsPerFragment(intersect_tree):
	'''
		counts the reads per fragment and generates appropriate output files
	'''
	
	if (options.verbose):
		print >> sys.stdout, "- %s START   : processing reads from bam file" % (timeStamp())

	samfile = pysam.Samfile(args[0], "rb" )

	samiter = samfile.fetch(until_eof=True)
	
	fragmentList={}
	fragmentPairs = {}
	
	readcounter = 0
	
	while(True):
		readpair = findNextReadPair(samiter)
		# if file contains any more reads, exit
		if (readpair[0].qname=="dummy"):
			break
		
		fragmentID1 = getFragment(samfile, readpair[0], intersect_tree, fragmentList)
		fragmentID2 = getFragment(samfile, readpair[1], intersect_tree, fragmentList)
		
		if (fragmentID1 == None or fragmentID2 == None):
			if (options.vverbose):
				print >> sys.stdout, "-- one read does not co-occur with any fragment: %d %d" % (fragmentID1, fragmentID2)
			continue
		
		f_tuple = tuple([min(fragmentID1, fragmentID2), max(fragmentID1, fragmentID2)])
		if (not fragmentPairs.has_key(f_tuple)):
			fragmentPairs[f_tuple] = 0
		fragmentPairs[f_tuple] += 1
		readcounter+=1
		
		if (options.verbose and readcounter % 1000000 == 0 ):
			print >> sys.stdout, "- %s         : %d read pairs processed" % (timeStamp(), readcounter)
	samfile.close()

	if (options.verbose):
		print >> sys.stdout, "- %s FINISHED: getting reads from bam file " % (timeStamp())

	return [ fragmentList, fragmentPairs ]	


def output(fragmentsMap , fragmentList, fragmentPairs):
	'''
	outputs 2 files, the first containing 
	"chr    extraField      fragmentMid     marginalizedContactCount        mappable? (0/1)"
	
	and the second containing:
	"chr1   fragmentMid1    chr2    fragmentMid2    contactCount"
	'''
	
	if (options.verbose):
		print >> sys.stdout, "- %s START   : output data " % (timeStamp())

	outfile1 = open(options.outputDir+os.path.basename(args[0])+".fragmentLists","w")
	
	fragmentIds = fragmentsMap.keys()
	fragmentIds.sort()

	for fragmentId in fragmentIds:

		mappable = 0
		contactCounts = 0

		if (fragmentList.has_key(fragmentId)):
			contactCounts = fragmentList[fragmentId]
			
		if (contactCounts>0):
			mappable = 1

		chrom = fragmentsMap[fragmentId][0]
		midpoint =  fragmentsMap[fragmentId][1]
		outfile1.write("%s\t%d\t%d\t%d\t%d\n" % (chrom, 0, midpoint, contactCounts, mappable))
		
	outfile1.close()
	
	outfile2 = open(options.outputDir+os.path.basename(args[0])+".contactCounts","w")
	for fragmentIds, contactCounts in fragmentPairs.iteritems():
		chrom1 = fragmentsMap[fragmentIds[0]][0]
		midpoint1 =  fragmentsMap[fragmentIds[0]][1]
	
		chrom2 = fragmentsMap[fragmentIds[1]][0]
		midpoint2 =  fragmentsMap[fragmentIds[1]][1]
	
		outfile2.write("%s\t%d\t%s\t%d\t%d\n" % (chrom1, midpoint1, chrom2, midpoint2, contactCounts))
		
	outfile2.close()
	
	if (options.verbose):
		print >> sys.stdout, "- %s FINISHED: output data" % (timeStamp())


def process():
	global options
	global args

	
	[ fragmentsMap, intersect_tree ] = createIntervalTrees()
	
	[ fragmentList, fragmentPairs ] = countReadsPerFragment(intersect_tree)
	
	output(fragmentsMap, fragmentList, fragmentPairs)
	
######################################
# main
######################################
if __name__ == "__main__":
	main()

