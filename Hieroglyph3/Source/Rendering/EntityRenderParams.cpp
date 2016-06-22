//--------------------------------------------------------------------------------
// This file is a portion of the Hieroglyph 3 Rendering Engine.  It is distributed
// under the MIT License, available in the root of this distribution and 
// at the following URL:
//
// http://www.opensource.org/licenses/mit-license.php
//
// Copyright (c) Jason Zink 
//--------------------------------------------------------------------------------

//--------------------------------------------------------------------------------
#include "PCH.h"
#include "EntityRenderParams.h"
#include "MaterialDX11.h"
#include "Log.h"
//--------------------------------------------------------------------------------
using namespace Glyph3;
//--------------------------------------------------------------------------------
EntityRenderParams::EntityRenderParams()
{
	iPass = GEOMETRY;
	WorldMatrix.MakeIdentity();
	Executor = nullptr;
	Material = nullptr;
}
//--------------------------------------------------------------------------------
EntityRenderParams::~EntityRenderParams()
{
	Executor = nullptr;
	Material = nullptr;
}
//--------------------------------------------------------------------------------
