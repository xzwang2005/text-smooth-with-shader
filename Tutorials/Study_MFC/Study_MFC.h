
// Study_MFC.h : main header file for the Study_MFC application
//
#pragma once

#ifndef __AFXWIN_H__
	#error "include 'stdafx.h' before including this file for PCH"
#endif

#include "resource.h"       // main symbols

// CStudy_MFCApp:
// See Study_MFC.cpp for the implementation of this class
//

class CStudy_MFCApp : public CWinApp
{
public:
	CStudy_MFCApp();

	Glyph3::Timer*			pTimer;
	Glyph3::RendererDX11*	pRenderer;
	Glyph3::EventManager*	pEventMgr;


// Overrides
public:
	virtual BOOL InitInstance();
	virtual int ExitInstance();

// Implementation
	afx_msg void OnAppAbout();
	afx_msg void OnSettings();
	DECLARE_MESSAGE_MAP()
	
};

extern CStudy_MFCApp theApp;
